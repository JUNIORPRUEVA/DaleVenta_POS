import crypto from 'node:crypto';
import http from 'node:http';
import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import jwt from 'jsonwebtoken';
import { Server } from 'socket.io';

import { normalizeJwtSecret } from '../auth/jwt.util';

type ClientSocket = {
  on(event: string, listener: (...args: any[]) => void): ClientSocket;
  connect(): void;
  disconnect(): void;
};

const createClient = ((require('socket.io-client') as { io: unknown }).io) as (
  url: string,
  options?: Record<string, unknown>,
) => ClientSocket;

const FULLTECH_ALLOWED_FULLPOS_COMPANY_ID = 2;

@Injectable()
export class CatalogRealtimeRelayService implements OnModuleDestroy {
  private readonly logger = new Logger(CatalogRealtimeRelayService.name);
  private readonly jwtSecret: string;
  private readonly fullposBaseUrl: string;
  private readonly fullposIntegrationToken: string;
  private io: Server | null = null;
  private upstream: ClientSocket | null = null;
  private started = false;

  constructor(private readonly config: ConfigService) {
    this.jwtSecret =
      normalizeJwtSecret(config.get<string>('JWT_SECRET')) ?? 'change-me';
    this.fullposBaseUrl = (
      config.get<string>('FULLPOS_INTEGRATION_BASE_URL') ?? ''
    )
      .trim()
      .replace(/\/$/, '');
    this.fullposIntegrationToken = (
      config.get<string>('FULLPOS_INTEGRATION_TOKEN') ?? ''
    ).trim();
  }

  attach(server: http.Server) {
    if (this.io) return;

    this.io = new Server(server, {
      cors: {
        origin: true,
        credentials: true,
      },
      transports: ['websocket', 'polling'],
    } as any);

    this.io.use((socket, next) => {
      try {
        const token =
          (socket.handshake.auth?.token as string | undefined) ??
          (socket.handshake.headers.authorization as string | undefined)?.replace(
            /^Bearer\s+/i,
            '',
          );

        if (!token) {
          return next(new Error('No autorizado'));
        }

        const payload = jwt.verify(token, this.jwtSecret) as {
          sub?: unknown;
          role?: unknown;
          companyId?: unknown;
          tokenType?: unknown;
        };

        // Persist minimal identity on the socket for room routing.
        socket.data.userId = payload?.sub?.toString?.() ?? '';
        socket.data.role = payload?.role?.toString?.() ?? '';
        socket.data.companyId = payload?.companyId?.toString?.() ?? '';
        return next();
      } catch {
        return next(new Error('No autorizado'));
      }
    });

    this.io.on('connection', (socket) => {
      socket.join('catalog');

      // Operations realtime rooms.
      socket.join('ops');

      const userId = (socket.data.userId ?? '').toString().trim();
      if (userId) {
        socket.join(`ops:user:${userId}`);
      }

      const companyId = (socket.data.companyId ?? '').toString().trim();
      if (companyId) {
        socket.join(`company:${companyId}`);
      }

      const role = (socket.data.role ?? '').toString().trim().toLowerCase();
      if (role) {
        socket.join(`ops:role:${role}`);
      }
    });
  }

  emitTo(room: string, event: string, payload: unknown) {
    this.io?.to(room).emit(event, payload);
  }

  emitOps(event: string, payload: unknown) {
    this.emitTo('ops', event, payload);
  }

  emitCompany(companyId: string, event: string, payload: unknown) {
    const room = `company:${companyId.trim()}`;
    this.emitTo(room, event, payload);
  }

  start() {
    if (this.started) return;
    this.started = true;

    if (!this.fullposBaseUrl || !this.fullposIntegrationToken) {
      this.logger.warn(
        'Realtime relay disabled: FULLPOS_INTEGRATION_BASE_URL or FULLPOS_INTEGRATION_TOKEN missing',
      );
      return;
    }

    const upstream = createClient(this.fullposBaseUrl, {
      transports: ['websocket'],
      autoConnect: false,
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1500,
      auth: {
        token: this.fullposIntegrationToken,
        expectedCompanyId: FULLTECH_ALLOWED_FULLPOS_COMPANY_ID,
      },
    });

    upstream.on('connect', () => {
      this.logger.log(
        `Catalog realtime relay connected to FULLPOS company ${FULLTECH_ALLOWED_FULLPOS_COMPANY_ID}`,
      );
    });

    upstream.on('connect_error', (error: Error) => {
      this.logger.warn(`Catalog realtime relay connect error: ${error.message}`);
    });

    upstream.on('disconnect', (reason: string) => {
      this.logger.warn(`Catalog realtime relay disconnected: ${reason}`);
    });

    upstream.on('product.event', (payload: unknown) => {
      if (!this.io) return;
      if (!payload || typeof payload !== 'object') return;

      this.io.to('catalog').emit('product.event', {
        eventId:
          (payload as { eventId?: unknown }).eventId?.toString() ??
          crypto.randomUUID(),
        type:
          (payload as { type?: unknown }).type?.toString() ?? 'product.updated',
        product: (payload as { product?: unknown }).product,
      });
    });

    upstream.connect();
    this.upstream = upstream;
  }

  onModuleDestroy() {
    this.upstream?.disconnect();
    this.upstream = null;
    this.io?.close();
    this.io = null;
  }
}
