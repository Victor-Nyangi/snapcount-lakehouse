# snapcount-lakehouse

NFL seasons from the raw [nflverse](https://github.com/nflverse/nflverse-data) files to tested
gold tables on AWS: S3 bronze, Athena + Iceberg silver and gold built by dbt, all in Terraform.

Work in progress. See the runbook below once it lands.

## Data source and licence

Data comes from [nflverse-data](https://github.com/nflverse/nflverse-data) release files. nflverse
data is published under [CC-BY 4.0](https://github.com/nflverse/nflverse-data/blob/master/LICENSE.md);
credit to the nflverse project and its
contributors. This repository's code is MIT licensed.
