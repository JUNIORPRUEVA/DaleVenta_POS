import { PATH_METADATA } from "@nestjs/common/constants";
import type { Request, Response } from "express";

import {
  DosaWebhookController,
  isDosaWebhookEndpointEnabled,
} from "./dosa-webhook.controller";
import type {
  DosaWebhookOutcome,
  DosaWebhookService,
} from "./dosa-webhook.service";

/**
 * Frontera HTTP del webhook DOSA.
 *
 * La ruta interna es `webhook/dosa` y no hay `setGlobalPrefix`: el proxy público
 * expone `/api/webhook/dosa` retirando el prefijo `/api`. Aquí se fija la ruta
 * real que atiende Nest y el comportamiento fail-closed del controlador.
 */

function fakeResponse() {
  const res = {
    status: jest.fn().mockReturnThis(),
    json: jest.fn().mockReturnThis(),
  };
  return res as unknown as Response & {
    status: jest.Mock;
    json: jest.Mock;
  };
}

function request(
  overrides: Partial<Request> = {},
): Request & { rawBody?: Buffer } {
  return {
    headers: { "x-dosa-signature": "t=1,v1=abc" },
    rawBody: Buffer.from('{"rnc":"133306001"}'),
    body: { rnc: "133306001" },
    ...overrides,
  } as unknown as Request & { rawBody?: Buffer };
}

function controllerWith(handle: jest.Mock) {
  return new DosaWebhookController({ handle } as unknown as DosaWebhookService);
}

describe("DosaWebhookController — frontera HTTP", () => {
  const original = process.env.DOSA_WEBHOOK_ENABLED;

  afterEach(() => {
    if (original === undefined) delete process.env.DOSA_WEBHOOK_ENABLED;
    else process.env.DOSA_WEBHOOK_ENABLED = original;
  });

  it("atiende la ruta interna `webhook/dosa`", () => {
    expect(
      Reflect.getMetadata(PATH_METADATA, DosaWebhookController.prototype.receive),
    ).toBe("webhook/dosa");
  });

  it.each(["", "false", "0", "yes"])(
    "con la bandera %p apagada responde 503 JSON y NO llama al servicio",
    async (value) => {
      process.env.DOSA_WEBHOOK_ENABLED = value;
      const handle = jest.fn();
      const controller = controllerWith(handle);
      const res = fakeResponse();

      await controller.receive(request(), res);

      expect(isDosaWebhookEndpointEnabled()).toBe(false);
      expect(handle).not.toHaveBeenCalled();
      expect(res.status).toHaveBeenCalledWith(503);
      expect(res.json).toHaveBeenCalledWith({
        accepted: false,
        code: "ECF_DOSA_WEBHOOK_DISABLED",
        reason: "ENDPOINT_DISABLED",
      });
    },
  );

  it("con la bandera activa entrega rawBody y cabeceras al servicio", async () => {
    process.env.DOSA_WEBHOOK_ENABLED = "true";
    const handle = jest.fn().mockResolvedValue({
      accepted: true,
      status: 200,
      duplicate: false,
      eventId: "event-1",
      code: "ECF_DOSA_WEBHOOK_RECORDED",
    } satisfies DosaWebhookOutcome);
    const controller = controllerWith(handle);
    const req = request();
    const res = fakeResponse();

    await controller.receive(req, res);

    expect(handle).toHaveBeenCalledWith({
      headers: req.headers,
      rawBody: req.rawBody,
      body: req.body,
    });
    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith({
      accepted: true,
      duplicate: false,
      eventId: "event-1",
      code: "ECF_DOSA_WEBHOOK_RECORDED",
    });
  });

  it("propaga un rechazo del servicio sin convertirlo en 200", async () => {
    process.env.DOSA_WEBHOOK_ENABLED = "true";
    const handle = jest.fn().mockResolvedValue({
      accepted: false,
      status: 503,
      code: "ECF_DOSA_WEBHOOK_BLOCKED",
      reason: "SIGNATURE_MISMATCH",
    } satisfies DosaWebhookOutcome);
    const controller = controllerWith(handle);
    const res = fakeResponse();

    await controller.receive(request(), res);

    expect(res.status).toHaveBeenCalledWith(503);
    expect(res.json).toHaveBeenCalledWith({
      accepted: false,
      code: "ECF_DOSA_WEBHOOK_BLOCKED",
      reason: "SIGNATURE_MISMATCH",
    });
  });
});
