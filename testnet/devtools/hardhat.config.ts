// LayerZero DevTools (topic 8) against the official testnets. Read-only use here: lz:oapp:config:get and
// lz:oapp:wire --dry-run. Owners are Safes now, so real changes go through testnet/safe-exec.sh.
import '@nomiclabs/hardhat-ethers'
import 'hardhat-deploy'
import '@layerzerolabs/toolbox-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import type { HardhatUserConfig } from 'hardhat/types'

process.loadEnvFile('../../.env') // RPCs and the deployer key live in the repo's .env (gitignored)
const accounts = process.env.TESTNET_PRIVATE_KEY ? [process.env.TESTNET_PRIVATE_KEY] : []

const config: HardhatUserConfig = {
    solidity: '0.8.24',
    networks: {
        sepolia: { eid: EndpointId.SEPOLIA_V2_TESTNET, url: process.env.SEPOLIA_RPC_URL!, accounts },
        'arbitrum-sepolia': { eid: EndpointId.ARBSEP_V2_TESTNET, url: process.env.ARBITRUM_SEPOLIA_RPC_URL!, accounts },
    },
}
export default config
