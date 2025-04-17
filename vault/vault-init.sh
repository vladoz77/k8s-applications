#! /usr/bin/bash
# Check if vault install
if ! vault --version; then
    echo "Please install vault"
    exit 1
fi

POD_STATUS=$(kubectl get po -n vault -o json | jq '.items[] |{name: .metadata.name, status: .status.phase}')

# VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)

