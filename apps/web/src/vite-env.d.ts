/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_POOL_SEPOLIA?: string;
  readonly VITE_POOL_MAINNET?: string;
  readonly VITE_FROM_BLOCK_SEPOLIA?: string;
  readonly VITE_FROM_BLOCK_MAINNET?: string;
  readonly VITE_RPC_SEPOLIA?: string;
  readonly VITE_RPC_MAINNET?: string;
  readonly VITE_BASE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
