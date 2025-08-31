# RAGFlow Notes

## Bringing up on EC2

EC2 instance type : t3.xlarge
OS: Amazon Linux 2023

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
