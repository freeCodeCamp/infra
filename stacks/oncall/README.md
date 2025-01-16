## Usage

This stack defines all the services for the housekeeping apps. See comments in the stack file for details. Note that for credentials we use the host docker `config.json` file. This requires the update service to be running on the same host (typically the manager node).

Also note that these credentials need to be updated if they expire. This file is located at `~/.docker/config.json`.
