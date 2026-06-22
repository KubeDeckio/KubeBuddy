## Is your feature request related to a problem? Please describe the impact that the lack of the feature requested is creating.

I am currently building a Headlamp plugin called KubeBuddy. It is not live or published yet. The plugin scans Kubernetes resources and reports findings such as missing resource requests, unhealthy workloads, RBAC overexposure, missing endpoints, and security misconfigurations.

For each finding, KubeBuddy can build useful troubleshooting context:

- check ID and name
- severity and category
- affected resource name, kind, namespace, and API version
- finding details
- KubeBuddy recommendation
- documentation link
- optional related resource data

Today there does not appear to be a supported way for another Headlamp plugin to open the AI Assistant panel with a prefilled prompt and structured context. The fallback is to provide a "Copy AI Prompt" button and ask the user to paste it manually, which is less integrated and makes AI-assisted troubleshooting feel disconnected from the finding the user is viewing.

## Describe the solution you'd like

I would like the Headlamp AI Assistant plugin to expose a supported integration point that lets other plugins open the AI panel with a prompt and optional structured context.

One possible API would be a browser event:

```ts
window.dispatchEvent(new CustomEvent('headlamp-ai:open', {
  detail: {
    prompt: 'Explain and troubleshoot this Kubernetes finding...',
    context: {
      sourcePlugin: 'kubebuddy',
      cluster: 'my-cluster',
      resource: {
        kind: 'Service',
        namespace: 'kube-system',
        name: 'network-observability',
        apiVersion: 'v1'
      },
      finding: {
        checkId: 'NET001',
        checkName: 'Services Without Endpoints',
        severity: 'high',
        details: 'No endpoints or endpoint slices'
      }
    }
  }
}));
```

The AI Assistant could then:

- open the existing right-side panel
- start a new chat or append to the current chat
- prefill the prompt, or optionally submit it automatically if explicitly requested
- include structured context in the assistant message

The integration should:

- no-op safely if AI Assistant is not installed or not configured
- expose whether AI Assistant is available/configured if possible
- avoid requiring plugins to import AI Assistant internals
- avoid sharing API keys or provider configuration with other plugins
- keep the user in control before executing any suggested changes

## What users will benefit from this feature?

Plugin developers would benefit because diagnostic, security, observability, and troubleshooting plugins could hand useful context to the AI Assistant without each plugin implementing its own AI provider configuration.

End users would benefit because they could move directly from a finding, event, or resource issue to AI-assisted explanation and remediation guidance inside the existing Headlamp AI Assistant experience.

This is likely most useful for:

- Headlamp Desktop users
- users with the AI Assistant plugin configured
- plugin developers building diagnostic or security plugins
- teams using Headlamp as a Kubernetes troubleshooting interface

## Are you able to implement this feature?

Yes, I can help propose a PR if the maintainers agree with the general approach and preferred API shape.

## Additional context

KubeBuddy is still in development, but the intended model is that it provides deterministic findings and recommendations, while AI Assistant can help explain, prioritize, and guide remediation using the finding context.

Example KubeBuddy actions that could use this integration:

- Troubleshoot with AI
- Explain finding
- Suggest fix
- Generate safe verification commands

Without this integration, KubeBuddy can only offer a "Copy AI Prompt" action and ask the user to paste the prompt into AI Assistant manually.
