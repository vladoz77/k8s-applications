Мы будем использовать Docker Compose для запуска Vault в Docker, а затем настроим HA Vault в Kubernetes для автоматического распечатывания через этот Vault.

 #### Настройка Vault в Docker с помощью Docker Compose

1. Создайте файл `docker-compose.yml` для запуска Vault:

```yaml
services:
  vault:
    container_name: vault
    image: hashicorp/vault
    restart: always
    environment:
      - VAULT_ADDR=http://0.0.0.0:8200
      - VAULT_API_ADDR=http://0.0.0.0:8200
      - VAULT_ADDRESS=http://0.0.0.0:8200
    volumes:
      - ./vault.json:/vault/config/vault.json
      - vault-data:/vault/file:rw
      - ./vault/policies:/vault/policies
    ports:
      - 8200:8200
    cap_add:
      - IPC_LOCK
    command: vault server -config=/vault/config/vault.json
volumes:
  vault-data:
```

2. Создайте файл конфигурации `vault.json`

```json
{
  "listener":  {
    "tcp":  {
      "address":  "0.0.0.0:8200",
      "tls_disable":  "true"
    }
  },
  "storage": {
    "file": {
      "path": "/vault/file"
    }
  },
  "default_lease_ttl": "168h",
  "max_lease_ttl": "720h",
  "api_addr": "http://0.0.0.0:8200",
  "ui" : "true"
}
```

3. Запустите Vault с помощью Docker Compose:

```bash
docker compose up -d --build
```

4. Подключитесь к Vault и выполните инициализацию:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init
```

Сохраните unseal keys и root token — они понадобятся для управления Vault.

5. Включите Transit Secret Engine:

```bash
vault secrets enable transit
```

6. Создайте ключ `unseal-key`, который будет использоваться для распечатывания HA Vault:

```bash
vault write -f transit/keys/autounseal
```

7. Создайте политику, которая разрешает только операции шифрования/дешифрования:

```bash
vault policy write autounseal -<<EOF
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
EOF
```

8. Создайте токен с ограниченными правами для использования Transit Secret Engine:

```bash
vault token create -orphan -policy="autounseal" \
   -wrap-ttl=120 -period=24h \
   -field=wrapping_token > wrapping-token.txt
```

Сохраните этот токен — он понадобится для настройки HA Vault в Kubernetes.