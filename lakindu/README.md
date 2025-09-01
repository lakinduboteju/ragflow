# RAGFlow Notes

## Bringing up on EC2

- EC2 instance type : t3.xlarge
- OS: Amazon Linux 2023

1. Install Docker
``` bash
cd ragflow
bash ./lakindu/ec2-install-docker.sh
```

2. Update VM max map count
``` bash
cd ragflow
bash ./lakindu/update_vm_max_map_count.sh
```

3. Bring up RAGFlow
``` bash
cd ragflow
bash ./lakindu/bring-up.sh
```

## Code Deep Dives

- `0-code-overview.md` - High-level architecture, codebase organization, technologies overview
- `1-rag.md` - RAG's Document Parsing and Chunking overview
- `2-rag.md` - RAG's Retrieval deep dive
