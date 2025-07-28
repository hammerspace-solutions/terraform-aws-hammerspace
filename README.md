# terraform-aws-ecgroups
This is a Terraform module and cannot stand on its own. It is meant to be included into a project as a module or to be uploaded to the Terraform Public Repository.

This module allows you to deploy either a standalone or HA Anvil plus zero or more DSX nodes.

All of the guard-rails for error free deployments are in the main Terraform project that would import this module. Except for one... Each module must verify that the requested EC2 instance is available in their availability zone. If this is not done, then Terraform could hang waiting for that resource to be available. 

## Table of Contents
- [Configuration](#configuration)
  - [Global Variables](#global-variables)
- [Component Variables](#component-variables)
  - [Hammerspace Variables](#hammerspace-variables)
- [Outputs](#outputs)

## Configuration

Configuration must be done in the main project by managing `terraform.tfvars`. Additionally, in the root of the main project, you must take the variables from this module and include them into root `variables.tf`. We recommend that you preface those variables with the module name, such that a variable in a module that looks like `ami =` is created as `ecgroups-ami =` in the root.

Then, in the root main.tf, you reference this module in the source. This is a sample for your root main.tf.

```module "hammerspace" {
  source = "git::https://github.com/your-username/terraform-aws-hammerspace.git?ref=v1.0.0"

  # ... provide the required variables for the module
  common_config = local.common_config
  instance_count = 2
  # ... etc.
}
```

## Module Variables

### Hammerspace Variables

These variables configure the Hammerspace deployment and are prefixed with `hammerspace_` in `terraform.tfvars`.

* **`hammerspace_profile_id`**: The name of an existing IAM Instance Profile to attach to Hammerspace instances. If left blank, a new one will be created.
* **`hammerspace_anvil_security_group_id`**: (Optional) An existing security group ID to use for the Anvil nodes.
* **`hammerspace_dsx_security_group_id`**: (Optional) An existing security group ID to use for the DSX nodes.
* `hammerspace_ami`: AMI ID for Hammerspace instances.
* `hammerspace_iam_admin_group_id`: IAM admin group ID for SSH access.
* `hammerspace_anvil_count`: Number of Anvil instances to deploy (0=none, 1=standalone, 2=HA) (Default: 0).
* `hammerspace_sa_anvil_destruction`: A safety switch to allow the destruction of a standalone Anvil. Must be set to true for 'terraform destroy' to succeed.
* `hammerspace_anvil_instance_type`: Instance type for Anvil metadata server (Default: "m5zn.12xlarge").
* `hammerspace_dsx_instance_type`: Instance type for DSX nodes (Default: "m5.xlarge").
* `hammerspace_dsx_count`: Number of DSX instances (Default: 1).
* `hammerspace_anvil_meta_disk_size`: Metadata disk size in GB for Anvil (Default: 1000).
* `hammerspace_anvil_meta_disk_type`: Type of EBS volume for Anvil metadata disk (Default: "gp3").
* `hammerspace_anvil_meta_disk_throughput`: Throughput for gp3 EBS volumes for the Anvil metadata disk (MiB/s).
* `hammerspace_anvil_meta_disk_iops`: IOPS for gp3/io1/io2 EBS volumes for the Anvil metadata disk.
* `hammerspace_dsx_ebs_size`: Size of each EBS Data volume per DSX node in GB (Default: 200).
* `hammerspace_dsx_ebs_type`: Type of each EBS Data volume for DSX (Default: "gp3").
* `hammerspace_dsx_ebs_iops`: IOPS for each EBS Data volume for DSX.
* `hammerspace_dsx_ebs_throughput`: Throughput for each EBS Data volume for DSX (MiB/s).
* `hammerspace_dsx_ebs_count`: Number of data EBS volumes to attach to each DSX instance (Default: 1).
* `hammerspace_dsx_add_vols`: Add non-boot EBS volumes as Hammerspace storage volumes (Default: true).

## Outputs

After a successful `apply`, this module will provide the following outputs. Sensitive values will be redacted and can be viewed with `terraform output <output_name>`.

* `ecgroup_nodes`: Details about the deployed ECGroup nodes.

The output will look something like this:

```
ecgroup_nodes = [
  [
    {
      "id" = "i-06d475c3e626e513a"
      "name" = "KadeTest-ecgroup-1"
      "private_ip" = "172.26.6.231"
    },
    {
      "id" = "i-0aec6b471c2261cc3"
      "name" = "KadeTest-ecgroup-2"
      "private_ip" = "172.26.6.75"
    },
    {
      "id" = "i-023ebb770c828b94e"
      "name" = "KadeTest-ecgroup-3"
      "private_ip" = "172.26.6.253"
    },
    {
      "id" = "i-0e1c8de4a0a06c1f5"
      "name" = "KadeTest-ecgroup-4"
      "private_ip" = "172.26.6.155"
    },
    {
      "id" = "i-09144f631094e8bce"
      "name" = "KadeTest-ecgroup-5"
      "private_ip" = "172.26.6.53"
    },
    {
      "id" = "i-0e2d302da59a2ab58"
      "name" = "KadeTest-ecgroup-6"
      "private_ip" = "172.26.6.95"
    },
  ],
]
```
