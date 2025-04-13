return function(conf, ctx)
  local core = require("apisix.core")
  local json = require("cjson")
  local http = require("resty.http")

  -- Parse JSON body
  local body_raw = core.request.get_body()
  if not body_raw then
    ngx.status = 400
    ngx.say("Error: Request body required")
    return
  end
  local body, err = json.decode(body_raw)
  if not body then
    ngx.status = 400
    ngx.say("Error: Invalid JSON - " .. err)
    return
  end

  -- Extract required fields
  local function_name = body.metadata and body.metadata.name
  local zip_data = body.zip_data
  if not function_name or not zip_data then
    ngx.status = 400
    ngx.say("Error: 'metadata.name' and 'zip_data' required")
    return
  end

  -- Decode zip from base64 using ngx.decode_base64
  local zip_binary, decode_err = ngx.decode_base64(zip_data)
  if not zip_binary then
    ngx.status = 400
    ngx.say("Error: Invalid base64 zip - " .. (decode_err or "unknown error"))
    return
  end

  -- Upload zip to MinIO
  local zip_path = function_name .. ".zip"
  local minio_url = "http://minio.serverless.svc.cluster.local:9000/functions/" .. zip_path
  local httpc = http.new()
  local resp, err = httpc:request_uri(minio_url, {
    method = "PUT",
    body = zip_binary
  })
  if not resp or resp.status ~= 200 then
    ngx.status = 500
    ngx.say("Error: Failed to upload zip to MinIO")
    return
  end

  -- Prepare Nuclio payload with proper scaling configuration
  local nuclio_payload = {
    metadata = body.metadata or { name = function_name },
    spec = {
      runtime = body.spec and body.spec.runtime or "python:3.9",
      handler = body.spec and body.spec.handler or "function:handler",
      disable = false,
      build = {
        path = minio_url,
        registry = (body.spec and body.spec.build and body.spec.build.registry) or "localhost:5000",
        commands = (body.spec and body.spec.build and body.spec.build.commands) or {}
      },
      env = body.spec and body.spec.env or nil,
      triggers = body.spec and body.spec.triggers or {
        http = {
          kind = "http",
          port = 8080
        }
      },
      resources = body.spec and body.spec.resources or nil,
      minReplicas = body.spec and body.spec.minReplicas or 1,  -- Moved to top level
      maxReplicas = body.spec and body.spec.maxReplicas or 4,  -- Moved to top level
      targetCPU = body.spec and body.spec.targetCPU or 90,     -- Moved to top level
    },
    namespace = "serverless"
  }

  -- Only include commands if provided in payload
  local commands = body.spec and body.spec.build and body.spec.build.commands
  if commands then
    nuclio_payload.spec.build.commands = commands
  end

  -- Convert payload to JSON
  local nuclio_body = json.encode(nuclio_payload)
  
  -- Debug: Print the payload being sent to Nuclio
  core.log.warn("Nuclio payload: ", nuclio_body)

  local nuclio_resp, nuclio_err = httpc:request_uri("http://nuclio-dashboard.serverless.svc.cluster.local:8070/api/functions/update", {
    method = "PUT",
    body = nuclio_body,
    headers = { ["Content-Type"] = "application/json" }
  })
  
  if not nuclio_resp then
    ngx.status = 500
    ngx.say("Error: Failed to deploy function - " .. (nuclio_err or "Unknown error"))
    return
  elseif nuclio_resp.status ~= 202 then
    ngx.status = 500
    ngx.say("Error: Failed to deploy function - Status " .. nuclio_resp.status .. ": " .. (nuclio_resp.body or "No details"))
    return
  end

  ngx.say("Function deployed successfully: " .. function_name)
end
