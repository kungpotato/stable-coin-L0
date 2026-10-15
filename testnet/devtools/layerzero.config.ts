// Desired state of Ping on the official testnets (topics 4 and 8), as LayerZero DevTools sees it.
// Addresses come from ../config.json (official deployments) and ../../lz-potato/deployments (ours).
import { readFileSync } from 'node:fs'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

process.loadEnvFile('../../.env')
const tn = JSON.parse(readFileSync('../config.json', 'utf8'))
const dep = (chainId: number) => JSON.parse(readFileSync(`../../lz-potato/deployments/${chainId}.json`, 'utf8'))

const sepolia: OmniPointHardhat = { eid: EndpointId.SEPOLIA_V2_TESTNET, address: dep(11155111).Ping }
const arbsep: OmniPointHardhat = { eid: EndpointId.ARBSEP_V2_TESTNET, address: dep(421614).Ping }

const S = tn.chains.sepolia
const A = tn.chains['arbitrum-sepolia']
const sorted = (xs: string[]) => [...xs].sort((a, b) => (a.toLowerCase() < b.toLowerCase() ? -1 : 1))

// one direction: `from` sends with its own libraries/DVNs, `to` receives with its own (sending chain's confirmations)
const edge = (from: typeof S, to: typeof S, confirmations: bigint) => ({
    sendLibrary: from.sendUln302,
    receiveLibraryConfig: { receiveLibrary: from.receiveUln302, gracePeriod: BigInt(0) },
    sendConfig: {
        executorConfig: { maxMessageSize: 10000, executor: from.executor },
        ulnConfig: {
            confirmations,
            requiredDVNs: sorted([from.dvns['layerzero-labs'], from.dvns.nethermind]),
            optionalDVNs: [],
            optionalDVNThreshold: 0,
        },
    },
    receiveConfig: {
        ulnConfig: {
            confirmations: BigInt(to === S ? S.defaultToArbSepolia.confirmations : A.defaultToSepolia.confirmations),
            requiredDVNs: sorted([from.dvns['layerzero-labs'], from.dvns.nethermind]),
            optionalDVNs: [],
            optionalDVNThreshold: 0,
        },
    },
})

const config: OAppOmniGraphHardhat = {
    contracts: [
        { contract: sepolia, config: { owner: process.env.SEPOLIA_SAFE_ADDRESS, delegate: process.env.SEPOLIA_SAFE_ADDRESS } },
        { contract: arbsep, config: { owner: process.env.ARBITRUM_SEPOLIA_SAFE_ADDRESS, delegate: process.env.ARBITRUM_SEPOLIA_SAFE_ADDRESS } },
    ],
    connections: [
        { from: sepolia, to: arbsep, config: edge(S, A, BigInt(S.defaultToArbSepolia.confirmations)) },
        { from: arbsep, to: sepolia, config: edge(A, S, BigInt(A.defaultToSepolia.confirmations)) },
    ],
}
export = config // CommonJS: the DevTools loader on Node 24 would otherwise see a nested default
