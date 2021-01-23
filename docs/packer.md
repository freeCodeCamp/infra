## Installation:

<https://www.packer.io/intro/getting-started/install>

## Usage:

### Login to Azure

First contact a staff member (an Azure Administrator) to get access to Azure, and login with:

  ```
  az login
  ```

### Create a service principal for "role based access control"

You need a new service principal to be able to execute the packer runs. Generate a new one like so:

  ```
  az ad sp create-for-rbac --role Contributor --query "{ client_id: appId, client_secret: password, tenant_id: tenant }" --name  MY_SERVICE_PRINCIPAL
  ```

  where MY_SERVICE_PRINCIPAL is something like 'sp-packer-example'.

  Output:

  ```
  {
    "client_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "client_secret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "tenant_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
  ```

Retrieve the subscription id:

  ```
  az account show --query "{ subscription_id: id }"
  ```


  Output:

  ```
  { "subscription_id": "17691967-bd37-4982-bb6b-e8de8c1e945e" }
  ```

Save the values from both the commands above for usage in upcoming steps. You can also create a service principal for role based access control via the Azure portal (following their documentation).

### Populate the environment env files with the keys

Copy the sample file

```
cp env.json.sample env.json
```

and add the keys as needed from the previous steps.

### Build AMI as per the requirement

#### Web Proxy (Ubuntu, NGINX)

```
packer build -var-file=env.json ami/nginx.json
```

#### TBD

