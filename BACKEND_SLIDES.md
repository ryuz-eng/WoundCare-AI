Slide 1 - Backend Goals
- Secure storage for wound images
- Scalable inference for large PyTorch models
- Simple integration with the Flutter client

Slide 2 - Architecture Overview
- Firebase Auth + Firestore for identity and metadata
- AWS S3 + KMS for encrypted object storage
- Lambda + API Gateway for upload-init
- EC2 FastAPI for inference

Slide 3 - Upload and Encryption Flow
- Client requests /upload-init
- Lambda returns pre-signed PUT + AES-GCM data key
- Client encrypts image and uploads ciphertext to S3
- Firestore stores s3Key, encryptedKeyB64, ivB64

Slide 4 - Inference Flow
- Client calls /infer with S3 key + encrypted key metadata
- EC2 decrypts via KMS
- Segmentation + 2-model ensemble classification
- Returns stage, confidence, mask, wound area

Slide 5 - Security Measures
- TLS enforced on S3
- SSE-KMS at rest
- Client-side AES-GCM
- Firebase ID token validation on EC2

Slide 6 - Why EC2
- Models are large and need persistent memory
- Avoid Lambda cold-start and size limits
- Stable CPU inference on t3.large

Slide 7 - Outcomes and Next Steps
- End-to-end pipeline working
- Add HTTPS via ALB + ACM if needed
- Add monitoring and autoscaling later
