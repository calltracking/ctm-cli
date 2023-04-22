#!/usr/bin/env python3

import os
import sys
import yaml
import json
import subprocess
from typing import List

# Define the path to the config file
CONFIG_FILE = "config.yml"

# Use yamllint to validate the YAML format
yaml_lint_output = subprocess.run(['yamllint', CONFIG_FILE], capture_output=True, text=True)

if yaml_lint_output.returncode != 0:
    print(f"Error: Invalid YAML format in {CONFIG_FILE}:")
    print(yaml_lint_output.stdout)
    sys.exit(1)

# Use the Python YAML library to load the config file to ensure it doesn't crash
try:
    with open(CONFIG_FILE, 'r') as config_file:
        config = yaml.safe_load(config_file)

    for env_key in ['development', 'staging', 'production']:
        cfg = config.get(env_key)
        if cfg is None:
            print(f"Error: Missing '{env_key}' key in {CONFIG_FILE}")
            sys.exit(1)

        for key in ['host', 'object', 'account']:
            if cfg.get(key) is None:
                print(f"Error: Missing '{key}' key in {CONFIG_FILE} for {env_key}\n\n{cfg}")
                sys.exit(1)

        obj = cfg['object']
        if 'code' in obj:
            if not os.path.exists('code.js'):
                print("Error: Missing code.js file")
                sys.exit(1)

            node_check = subprocess.run(["/usr/bin/env", "node", "-c", "code.js"])
            if node_check.returncode != 0:
                print("Error: code.js is not valid JavaScript")
                sys.exit(1)

except Exception as e:
    print(f"Error: Failed to load {CONFIG_FILE}: {e}")
    sys.exit(1)
