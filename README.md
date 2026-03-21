# Scaling on Satisfaction: Automated Rollouts Driven by User Feedback - GitOps

_Presented by Whitney Lee and Thomas Vitale at KubeCon+CloudNativeCon Europe 2026._

[Details](https://colocatedeventseu2026.sched.com/event/2DY2c/scaling-on-satisfaction-automated-rollouts-driven-by-user-feedback-thomas-vitale-systematic-whitney-lee-datadog)

As the old saying goes, “the customer is always right”. When it comes to GenAI, the end users of our apps are indeed always right, because we can’t fully trust an LLM on its own. What if we used a new mechanism to guide the routing and rollout of new application versions? How about user feedback? Imagine that: the more an app variant gets up-voted, the more traffic is sent to it.

In this session, Whitney and Thomas demo a platform that enables app developers to define success criteria for business operations involving GenAI, and to capture users’ feedback using OpenTelemetry - including how to correlate it with other observability data. Then comes the twist. They’ll expand the platform using Flagger and Knative so that the users control the rollout and routing of new apps. And today, YOU are the user, the audience!

You’ll see how this technique can be applied beyond GenAI, and take part in an interactive story that evolves and changes course in real time based on your feedback!

## Development environment

This project uses [Flox](https://flox.dev/) to manage the development and build environment via [Nix](https://nixos.org). After [installing](https://flox.dev/docs/install-flox/install/) the Flox CLI (open-source), activate the environment:

```shell
flox activate
```

By doing so, you will have access to all the tools and dependencies needed to provision a Kubernetes cluster, install the Kadras Engineering Platform, and deploy the applications.

## Platform

This project relies on the Kadras Engineering Platform, an open-source project that provides common platform capabilities for building and operating cloud-native applications. The platform is built on top of Kubernetes and includes components such as Crossplane, Flagger, Knative, Contour, OpenTelemetry, and more.

We installed the platform on a Kubernetes cluster hosted at Hetzner, a European cloud provider. You can follow the installation instructions in the [Kadras documentation](https://kadras-io.github.io/kadras-docs/docs/hetzner/installation/) to set up your own instance of the platform.

The configuration of the platform is defined in the `values.yaml` file you can find in the root folder of this project. You should reference it when installing the platform based on the instructions in the documentation.

Our project relies on a few additional Secrets that you will need to create in your cluster.

For Mistral AI:

```shell
kubectl create secret generic mistral-ai \
  --namespace apps \
  --from-literal=api-key="<your-mistral-api-key>"
```

For Anthropic:

```shell
kubectl create secret generic anthropic \
  --namespace apps \
  --from-literal=api-key="<your-anthropic-api-key>"
```

For Datadog:

```shell
kubectl create secret generic datadog-secret \
  --namespace observability \
  --from-literal=api-key="<your-datadog-api-key>"
```

For the application admin account:

```shell
kubectl create secret generic admin-credentials \
  --namespace apps \
  --from-literal=username="<admin-username>" \
  --from-literal=password="<admin-password>"
```

## Application

The application source code is available in two variants:

- The [original NodeJS version](https://github.com/wiggitywhitney/scaling-on-satisfaction) built by Whitney Lee.
- The [Java variant](https://github.com/ThomasVitale/scaling-on-satisfaction) built by Thomas Vitale.
