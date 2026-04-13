import { Link, Navigate, Route, Routes } from "react-router-dom";
import { useWeb3 } from "./web3";
import { AboutPage } from "./pages/AboutPage";
import { DaoAppPage } from "./pages/DaoAppPage";
import { DaoStatePage } from "./pages/DaoStatePage";
import { deploymentForChain } from "./deployments";

export function App() {
  const { chainId, setChainId, account, connect, disconnect } = useWeb3();
  const dep = deploymentForChain(chainId);
  const poolOk = dep && dep.pool !== "0x0000000000000000000000000000000000000000";

  return (
    <div className="layout">
      <header>
        <strong>RttM DAO</strong>
        <nav>
          <Link to="/">State</Link>
          <Link to="/app">dApp</Link>
          <Link to="/about">About</Link>
        </nav>
        <select
          value={chainId}
          onChange={(e) => void setChainId(Number(e.target.value))}
          aria-label="Network"
        >
          <option value={11155111}>Sepolia (testnet)</option>
          <option value={1}>Ethereum mainnet</option>
        </select>
        {!account ? (
          <button type="button" onClick={() => void connect()}>
            Connect wallet
          </button>
        ) : (
          <>
            <span className="muted" title={account}>
              {account.slice(0, 6)}…{account.slice(-4)}
            </span>
            <button type="button" onClick={disconnect}>
              Disconnect
            </button>
          </>
        )}
      </header>
      {!poolOk && (
        <p className="err">
          No pool address for this chain. Set <code>VITE_POOL_SEPOLIA</code> /{" "}
          <code>VITE_POOL_MAINNET</code> when building.
        </p>
      )}
      <Routes>
        <Route path="/" element={<DaoStatePage />} />
        <Route path="/app" element={<DaoAppPage />} />
        <Route path="/about" element={<AboutPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </div>
  );
}
