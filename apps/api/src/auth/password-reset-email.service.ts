import { Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

type PasswordResetEmail = {
  to: string;
  resetUrl: string;
};

@Injectable()
export class PasswordResetEmailService {
  private readonly logger = new Logger(PasswordResetEmailService.name);

  constructor(private readonly config: ConfigService) {}

  async sendPasswordResetEmail(message: PasswordResetEmail) {
    const apiKey = (this.config.get<string>("RESEND_API_KEY") ?? "").trim();
    const from = (this.config.get<string>("EMAIL_FROM") ?? "").trim();

    if (!apiKey || !from) {
      this.logger.warn(
        "Password reset email not sent: configure RESEND_API_KEY and EMAIL_FROM.",
      );
      return { sent: false, provider: "unconfigured" };
    }

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [message.to],
        subject: "Recupera tu acceso a FullPOS Cloud",
        html: this.renderHtml(message.resetUrl),
        text: this.renderText(message.resetUrl),
      }),
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      this.logger.warn(
        `Password reset email provider failed: ${response.status} ${detail.slice(0, 180)}`,
      );
      return { sent: false, provider: "resend" };
    }

    return { sent: true, provider: "resend" };
  }

  private renderText(resetUrl: string) {
    return [
      "Recupera tu acceso a FullPOS Cloud",
      "",
      "Recibimos una solicitud para restablecer la contraseña de tu cuenta empresarial.",
      "",
      `Restablecer contraseña: ${resetUrl}`,
      "",
      "Este enlace expira en 30 minutos. Si no realizaste esta solicitud, puedes ignorar este mensaje.",
    ].join("\n");
  }

  private renderHtml(resetUrl: string) {
    const escapedUrl = this.escapeHtml(resetUrl);
    return `
      <div style="font-family:Arial,sans-serif;line-height:1.5;color:#172033">
        <h1 style="font-size:22px">Recupera tu acceso a FullPOS Cloud</h1>
        <p>Recibimos una solicitud para restablecer la contraseña de tu cuenta empresarial.</p>
        <p>
          <a href="${escapedUrl}" style="display:inline-block;background:#1957E6;color:#fff;text-decoration:none;padding:12px 18px;border-radius:8px;font-weight:700">
            Restablecer contraseña
          </a>
        </p>
        <p>Este enlace expira en 30 minutos. Si no realizaste esta solicitud, puedes ignorar este mensaje.</p>
      </div>
    `;
  }

  private escapeHtml(value: string) {
    return value
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }
}
