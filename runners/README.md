# Action runners deployment

## On AWS

This config shows how to create GitHub action runners on AWS. This is based on
the "ubuntu" example here:
https://github.com/philips-labs/terraform-aws-github-runner, please read the
guidelines available there.

### Installing & configuring

1. Download the Lambda zip files.

   ```console
   cd lambdas
   terraform init
   terraform apply
   cd ..
   ```

2. Before running Terraform, ensure the GitHub app is configured. Follow the
   instructions in the guidelines mentioned earlier.

3. Provision the Infrastructure

   You will need the GitHub App ID, and the base64 encoded GitHub App private
   the key you generated in .pem format.

   ```console
   terraform init
   terraform plan -var='github_app_id=XXXXXX' -var="github_app_key_base64=xxxxxxxxxxxxxxxxxxxxxxxxxx"
   terraform apply -var='github_app_id=XXXXXX' -var="github_app_key_base64=xxxxxxxxxxxxxxxxxxxxxxxxxx"
   ```

4. You can receive the webhook details by running:

   ```console
   terraform output -raw webhook_secret
   ```

   > Be aware some shells will print some end of line character `%`.
