#!/usr/bin/env python3

import os
import sys
import yaml
import json
import subprocess
from typing import List

BRANCHES = ['release-production', 'release-staging', 'release-development']

current_branch = subprocess.check_output(
    ['git', 'rev-parse', '--abbrev-ref', 'HEAD']).decode('utf-8').strip()

if current_branch in BRANCHES:
    env = current_branch.split('-')[-1]
    with open("config.yml", 'r') as config_file:
        config = yaml.safe_load(config_file)
        env_config = config[env]

    host = env_config['host']
    account = env_config['account']
    obj = env_config['object']
    if 'code' in obj:
        with open('code.js', 'r') as code_file:
            obj['code'] = code_file.read()

    # Prompt the user for the API key
    api_key = input(f"Enter your API key for branch {current_branch}:")

    print(f"deploying {json.dumps(obj, indent=2)}")

    wrap = {
        'lambda_action': obj
    }

    command = f"curl -u{api_key} -XPATCH -H'Content-Type:application/json' 'https://{host}/api/v1/accounts/{account}/lambdas/{obj['id']}' -d'{json.dumps(wrap)}'"
    os.system(command)
