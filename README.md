# AutoOps Lab Environment

A complete lab environment for testing and demonstrating AutoOps agent capabilities with Elasticsearch cluster management. This setup creates a controlled environment with intentional issues for the AutoOps agent to detect and resolve.

## Overview

This lab environment consists of:
- A Multipass VM running Docker
- Elasticsearch
- Scripts to introduce various cluster health issues
- AutoOps agent installation and configuration tools

## Prerequisites

- [Multipass](https://multipass.run/) installed on your system
- At least 4GB of available RAM
- 10GB of available disk space
- Internet connection for downloading Docker images

## Quick Start

### 1. Create the Lab Environment

```bash
./create_autoops_lab.sh
```

This script will:
- Clean up any existing AutoOps VM instances
- Launch a new Multipass VM with Docker
- Start Elasticsearch
- Introduce various cluster issues
- Display your Elasticsearch credentials

### 2. Install the AutoOps Agent

```bash
./install_autoops_agent.py
```

This interactive script will:
- Prompt you to paste your AutoOps agent `docker run` command
- Automatically detect and replace the API key placeholder
- Override configuration to use `localhost:9200`
- Configure host networking mode
- Handle container cleanup and deployment

**What to paste**: Copy the `docker run` command from your AutoOps dashboard. The script will handle the rest.

### 3. Verify the Setup

Check that everything is running:

```bash
# View VM status
multipass info autoops

# Check containers
multipass exec autoops -- docker ps

# View AutoOps agent logs
multipass exec autoops -- docker logs -f <agent-container-name>
```

### Complete Lab Teardown

```bash
./cleanup_autoops_lab.sh
```

## Warning

This lab environment is provided as-is for testing and demonstration purposes.
