## Flowcy One-Click Deployment

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMoimHossain%2Fflowcy-backend%2Fmain%2Fazuredeploy.json)

Clicking the button pre-loads the `azuredeploy.json` template that provisions:

- Azure Cosmos DB account plus the `stellaris` database (throughput is configurable).
- Log Analytics workspace wired to an Azure Container Apps environment.
- Two Container Apps pointing at the public Docker Hub images:
	- `moimhossain/azdo-control-panel:v2` (web API with external ingress).
	- `moimhossain/azdo-control-panel-daemon:v2` (background daemon, no ingress).

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `namePrefix` | Short prefix applied to workspace, Container Apps, and Log Analytics names. Stick to 3-12 lowercase letters or digits. |
| `cosmosAccountName` | Globally unique Cosmos DB account name (lowercase letters and digits only). Defaults to a generated string if left unchanged. |
| `devOpsOrgName` | Azure DevOps organization Flowcy should manage. This value becomes `AZURE_DEVOPS_ORGNAME` in both containers. |
| `webPatSecret` | Secure PAT the Web API uses for elevated Azure DevOps operations. |
| `daemonPatSecret` | Secure PAT for the daemon. Reuse the same value as the Web PAT if you do not need separation. |

### Optional Parameters

- `cosmosDatabaseName` / `cosmosDatabaseThroughput` – keep defaults unless you already have a populated database.
- `webImage` / `daemonImage` – override if you publish custom images.
- Replica counts, CPU, and memory knobs control Container Apps scale and sizing.
- `webContainerCpu` / `daemonContainerCpu` – accept decimal values such as `0.5`; when deploying via CLI, pass them as quoted strings (the template converts them to numbers internally).


### Post-Deployment Checklist

1. Note the `webAppFqdn` output (public URL for the Web API).
2. Grant the PATs sufficient rights (Project Collection Administrator or equivalent) in the target Azure DevOps org.
3. If you need organization-specific PAT secrets, update each Container App to add `AZURE_DEVOPS_PAT__<ORG>` environment variables after deployment.
4. Configure any additional Cosmos containers/collections if your workload requires more than the default database scaffold.

### Working from Bicep

- `azuredeploy.bicep` is the source template. Run `bicep build azuredeploy.bicep --outfile azuredeploy.json` before committing so the button keeps pointing at the up-to-date JSON artifact.
- To deploy from the CLI instead of the portal, use `az deployment group create --resource-group <rg> --template-file azuredeploy.bicep --parameters <key>=<value> ...`.