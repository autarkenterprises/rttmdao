import { deploymentForChain } from "../deployments";
import { useWeb3 } from "../web3";

export function usePoolDeployment() {
  const { chainId } = useWeb3();
  const dep = deploymentForChain(chainId);
  const valid =
    dep !== undefined && dep.pool !== "0x0000000000000000000000000000000000000000";
  return { chainId, pool: valid ? dep.pool : undefined, fromBlock: dep?.fromBlock };
}
