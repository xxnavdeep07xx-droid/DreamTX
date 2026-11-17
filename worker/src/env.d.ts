/// Runtime bindings for the DreamTX worker.
export interface Env {
  /** Pairing registry: token -> deck binding, TTL, attempt counters. */
  REGISTRY: DurableObjectNamespace;
  /** One Durable Object per deck: authoritative state, version log, WS. */
  DECKS: DurableObjectNamespace;
}

/** JSON value alias used across the MCP + engine boundary. */
export type Json = string | number | boolean | null | Json[] | { [k: string]: Json };

/** Minimal JSON-RPC 2.0 envelope. */
export interface RpcRequest {
  jsonrpc: "2.0";
  id?: Json;
  method: string;
  params?: Record<string, Json>;
}

export interface RpcResponse {
  jsonrpc: "2.0";
  id?: Json;
  result?: Json;
  error?: { code: number; message: string; data?: Json };
}
