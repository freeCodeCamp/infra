# Usage

Once the stackscript is provisioned using the terraform config in this folder, you can use it as a resource elsewhere like so:

```hcl
  resource "linode_instance" "test" {
    image           = "linode/..."
    type            = " ... "
    stackscript_id  = "<REPLACE WITH THE ID OF THE STACKSCRIPT>"
    region          = " ... "
    authorized_keys = [ ... ]

    stackscript_data = {
      "userdata" = "<REPLACE WITH BASE64 ENCODED USERDATA>"
    }
  }
```
