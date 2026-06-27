# Changes Summary

Remapped model calls to use the working `minimaxai/minimax-m3` model for OpenLingo connectivity instead of `gpt-4o` or `deepseek-ai/deepseek-v4-pro`.

## File Modifications

### 1. `openlingo-debug/lib/nvidia-fix.ts`
- **Updated interceptor conditions**: Handled both `gpt-4o` and `deepseek-ai/deepseek-v4-pro` model request mapping.
- **Model remapping**: Routed requests for those models to `minimaxai/minimax-m3`.
- **Payload handling (`chat_template_kwargs`)**: Cleaned up the request body by deleting the `chat_template_kwargs` field when routing to Minimax M3, preventing schema validation or model-compatibility issues.

### 2. `openlingo-debug/lib/constants.ts`
- **Updated default model**: Changed the `DEFAULT_AI_MODEL` constant from `deepseek-ai/deepseek-v4-pro` to `minimaxai/minimax-m3`.

## Verification Details

- **Docker Image Build**: Successfully ran `./k3s-build.sh ./openlingo-debug 192.168.0.236:5000/openlingo:v4-timeout-fix` to build and push the new image.
- **Deployment Rollout**: Triggered a rollout restart using `kubectl rollout restart deployment openlingo -n openlingo`.
- **Rollout Status**: Successfully verified rollout completion.
- **Log Verification**: Checked pod initialization logs and confirmed that the server started successfully and log message `[NIM-FORCE] Global interceptor and model mapper active` is printed.
