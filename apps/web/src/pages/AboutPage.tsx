export function AboutPage() {
  return (
    <div>
      <h1>About RttM DAO</h1>
      <p>
        This interface talks to an <strong>RttmPool</strong> contract: a single-treasury-asset vault (e.g. USDC) with
        share voting, gated membership via <code>applyJoin</code> + governance approval, dues, kicks, and configurable
        BPS thresholds for votes.
      </p>
      <p>
        Use the <strong>network</strong> selector for Sepolia vs mainnet. Pool addresses are baked in at build time
        from <code>VITE_POOL_SEPOLIA</code> and <code>VITE_POOL_MAINNET</code>.
      </p>
      <p>
        See the repository <code>docs/DAO.md</code> for the full parameter matrix, factory flow, BPS voting, and how
        each value can be changed.
      </p>
    </div>
  );
}
