# Install tempo
helm repo add grafana https://grafana.github.io/helm-charts
helm install tempo grafana/tempo-distributed -f tempo-values.yml --namespace tracing

# Ingress NGINX traces integration
controller:
  config:
    # Open Tracing
    enable-opentracing: "true"
    zipkin-collector-host: tracing-tempo-distributor.tracing.svc.cluster.local
    zipkin-service-name: nginx-internal
    log-format-escape-json: "true"
    log-format-upstream: '{"source": "nginx", "time": $msec, "resp_body_size": $body_bytes_sent, "request_host": "$http_host", "request_address": "$remote_addr", "request_length": $request_length, "method": "$request_method", "uri": "$request_uri", "status": $status,  "user_agent": "$http_user_agent", "resp_time": $request_time, "upstream_addr": "$upstream_addr", "trace_id": "$opentracing_context_x_b3_traceid", "span_id": "$opentracing_context_x_b3_spanid"}'

# Grafana Configuration
grafana:
  # Additional data source
  additionalDataSources:
  - name: Tempo
    type: tempo
    uid: tempo
    access: proxy
    url: http://tempo-query-frontend.tracing.svc.cluster.local:3100

# Loki and Tempo integration
grafana
  additionalDataSources:
  - name: Loki
    type: loki
    uid: loki
    access: proxy
    url: http://loki-gateway.logging.svc.cluster.local
    jsonData:
      derivedFields:
        # Traefik traces integration
        # - datasourceUid: tempo
        #   matcherRegex: '"request_X-B3-Traceid":"(\w+)"'
        #   name: TraceID
        #   url: $${__value.raw}
          # NGINX traces integration
        - datasourceUid: tempo
          matcherRegex: '"trace_id": "(\w+)"'
          name: TraceID
          url: $${__value.raw}
  - name: Tempo
    uid: tempo
    type: tempo
    access: proxy
    url: http://tempo-query-frontend.tracing.svc.cluster.local:3100