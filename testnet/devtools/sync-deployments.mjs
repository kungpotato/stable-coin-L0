// Our contracts are deployed with forge (lz-potato). LayerZero DevTools reads ABIs from hardhat-deploy's
// deployments/<network>/<Name>.json, so generate those from the forge artifacts + lz-potato/deployments.
// usage: node sync-deployments.mjs     (output is gitignored; rerun after any redeploy)
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'

const contracts = { Ping: 'PingOApp' } // deployments key -> forge contract name
const networks = { sepolia: 11155111, 'arbitrum-sepolia': 421614 }
for (const [network, chainId] of Object.entries(networks)) {
    const recorded = JSON.parse(readFileSync(`../../lz-potato/deployments/${chainId}.json`, 'utf8'))
    mkdirSync(`deployments/${network}`, { recursive: true })
    writeFileSync(`deployments/${network}/.chainId`, String(chainId))
    for (const [key, name] of Object.entries(contracts)) {
        const { abi } = JSON.parse(readFileSync(`../../lz-potato/out/${name}.sol/${name}.json`, 'utf8'))
        writeFileSync(`deployments/${network}/${name}.json`, JSON.stringify({ address: recorded[key], abi }, null, 2))
        console.log(`${network}: ${name} ${recorded[key]}`)
    }
}
