# Providers (0.4.0)

Select Settings → Provider and API key. Choose a preset, enter its API key and save. The model list comes from that service. If the service does not offer GET /models, enter the exact model ID and use Save without testing. Listing models tests connectivity, not generation entitlement or balance. A ChatGPT/Claude/Gemini web subscription is not an API key.

For local servers use the computer's LAN IP, not 127.0.0.1 (which is the iPad/iPhone itself). Local servers may omit the key. All presets allow editing the URL. Custom profiles cover other endpoints implementing one of the four supported protocols. Azure v1 needs a resource URL such as https://RESOURCE.openai.azure.com/openai/v1 and a deployment name as the model. Dated Azure API URLs and AWS SigV4/IAM endpoints are not directly supported; they need a compatible gateway.

Each preset remembers its URL, format and selected model. Credentials/model choices/caches are scoped to the normalized endpoint and protocol. Changing an address clears the editor's key field so an existing key is not silently sent elsewhere. History retains its original provider identity; switching services does not automatically send old conversations to the new service. Existing OpenRouter data retains its original keychain account and cache.

Only OpenRouter receives its web/file-parser/compression plugins. Other providers receive standard text/chat/image requests only. Unknown model capabilities/prices are not advertised as free or vision-capable. Use the image-input switch for a manually selected model known to accept images. PDF parsing remains an OpenRouter feature; convert PDFs to text for other services. Model/provider capabilities and account access can differ.

## Protocol sources

- OpenAI Chat Completions: https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
- Responses streaming: https://developers.openai.com/api/docs/guides/streaming-responses
- Anthropic Messages/authentication: https://platform.claude.com/docs/en/api/overview
- OpenRouter: https://openrouter.ai/docs/api/reference/overview
- Gemini compatibility: https://ai.google.dev/gemini-api/docs/openai
- Groq: https://console.groq.com/docs/openai
- DeepSeek: https://api-docs.deepseek.com/quick_start/
- Mistral: https://docs.mistral.ai/resources/migration-guides
- xAI: https://docs.x.ai/developers/rest-api-reference/inference/chat-completions
- Together: https://docs.together.ai/docs/inference/openai-compatibility
- Fireworks: https://docs.fireworks.ai/tools-sdks/openai-compatibility
- Cohere: https://docs.cohere.com/docs/compatibility-api
- Hugging Face: https://huggingface.co/docs/inference-providers/index
- SambaNova: https://github.com/sambanova/ai-starter-kit/blob/main/quickstart/README.md
- Cerebras: https://inference-docs.cerebras.ai/resources/openai
- NVIDIA: https://docs.nvidia.com/aiq-blueprint/2.2.0-rc1/customization/swapping-models.html
- Perplexity Agent API: https://docs.perplexity.ai/docs/agent-api/openai-compatibility
- Ollama local/cloud: https://docs.ollama.com/api/openai-compatibility
- LM Studio: https://lmstudio.ai/docs/developer/openai-compat
- Azure v1: https://learn.microsoft.com/en-us/azure/foundry/openai/api-version-lifecycle

Sources checked 2026-10-26. GitHub Models is intentionally omitted: GitHub documents its retirement on July 30, 2026 (https://docs.github.com/en/github-models).

On-device regression tests run only with Documents/debug present. aichat:provider-tests reads Documents/provider-test-config.json containing a loopback fixture server URL and writes tmp/provider-tests.json. Tests never use a real API key or paid generation. Real paid-provider success still requires a valid key, model and account access.
