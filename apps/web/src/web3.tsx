import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  type Chain,
  createPublicClient,
  createWalletClient,
  custom,
  http,
  type PublicClient,
  type WalletClient,
} from "viem";
import { mainnet, sepolia } from "viem/chains";

type EthReq = { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> };

function getEthereum(): EthReq | undefined {
  return (typeof window !== "undefined" && (window as unknown as { ethereum?: EthReq }).ethereum) || undefined;
}

const CHAINS: Record<number, Chain> = {
  1: mainnet,
  11155111: sepolia,
};

function transportFor(chainId: number) {
  if (chainId === 11155111) {
    return http(import.meta.env.VITE_RPC_SEPOLIA || "https://rpc.sepolia.org");
  }
  return http(import.meta.env.VITE_RPC_MAINNET || "https://eth.llamarpc.com");
}

type Web3Ctx = {
  chainId: number;
  setChainId: (id: number) => void;
  account: `0x${string}` | null;
  publicClient: PublicClient;
  walletClient: WalletClient | undefined;
  connect: () => Promise<void>;
  disconnect: () => void;
};

const Ctx = createContext<Web3Ctx | null>(null);

export function useWeb3() {
  const v = useContext(Ctx);
  if (!v) throw new Error("Web3Provider missing");
  return v;
}

export function Web3Provider({ children }: { children: ReactNode }) {
  const [chainId, setChainIdState] = useState(11155111);
  const [account, setAccount] = useState<`0x${string}` | null>(null);

  const chain = CHAINS[chainId] ?? sepolia;

  const publicClient = useMemo(
    () => createPublicClient({ chain, transport: transportFor(chainId) }),
    [chain, chainId],
  );

  const walletClient = useMemo(() => {
    if (!account) return undefined;
    const eth = getEthereum();
    if (!eth) return undefined;
    return createWalletClient({ account, chain, transport: custom(eth) });
  }, [account, chain]);

  const setChainId = useCallback(
    async (id: number) => {
      setChainIdState(id);
      const eth = getEthereum();
      if (!eth) return;
      try {
        await eth.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: `0x${id.toString(16)}` }],
        });
      } catch {
        /* user may reject; UI still switches read client */
      }
    },
    [],
  );

  const connect = useCallback(async () => {
    const eth = getEthereum();
    if (!eth) throw new Error("No injected wallet (e.g. MetaMask).");
    const accs = (await eth.request({ method: "eth_requestAccounts" })) as string[];
    const a = accs[0] as `0x${string}`;
    setAccount(a);
    try {
      await eth.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: `0x${chainId.toString(16)}` }],
      });
    } catch {
      /* optional */
    }
  }, [chainId]);

  const disconnect = useCallback(() => setAccount(null), []);

  const value = useMemo(
    () => ({
      chainId,
      setChainId,
      account,
      publicClient,
      walletClient,
      connect,
      disconnect,
    }),
    [chainId, setChainId, account, publicClient, walletClient, connect, disconnect],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
