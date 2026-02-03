# WoundCare AI Tablet - Handoff Guide

This README summarizes the end-to-end setup built for this project:
- Flutter app uses Firebase Auth + Firestore.
- Images are encrypted client-side (AES-GCM), stored in S3 with SSE-KMS.
- EC2 runs FastAPI inference, decrypts via KMS, runs segmentation + 2-model ensemble, returns results.
- API Gateway + Lambda issues pre-signed S3 upload URLs.

## Architecture Overview

Client (Flutter)
1) User logs in with Firebase Auth.
2) App requests /upload-init from API Gateway (Lambda).
3) App encrypts image (AES-GCM) and uploads ciphertext to S3 via pre-signed PUT URL.
4) App saves metadata to Firestore (s3Key, encryptedKeyB64, ivB64, etc.).
5) App calls EC2 /infer to decrypt + run models and display results.

AWS
- S3: woundcare-uploads bucket (private, SSE-KMS enforced)
- KMS: symmetric key for S3 SSE-KMS and data key generation
- Lambda: returns pre-signed PUT URL + data key for client-side encryption
- API Gateway (HTTP API): /upload-init -> Lambda
- EC2: FastAPI server that loads models and runs inference (/infer and /download-url)

## Flutter App Changes

Key files
- lib/screens/login_screen.dart: email/password auth + forgot password
- lib/services/auth_service.dart: sign in / create + session refresh
- lib/screens/capture_screen.dart: encrypt + upload + save Firestore metadata
- lib/screens/analysis_screen.dart: calls EC2 /infer (with auth header)
- lib/utils/constants.dart: URLs + KMS key ARN

Constants
Update these in lib/utils/constants.dart if endpoints change:

static const String uploadInitUrl = "https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/upload-init";
static const String kmsKeyArn = "arn:aws:kms:us-east-1:<account-id>:key/<key-id>";
static const String inferUrl = "http://34.195.129.250:7860/infer";
static const String baseUrl = "http://34.195.129.250:7860";

## Firebase Setup

1) Create Firebase project
2) Enable Authentication -> Email/Password
3) Enable Firestore
4) Run FlutterFire CLI:

flutterfire configure --project=<firebase-project-id>

## AWS: KMS Key

Create a symmetric key and add LabRole as a key user.
Keep the default key policy. Copy the Key ARN.

## AWS: S3 Bucket (Images)

Create bucket woundcare-uploads:
- Block public access ON
- Versioning ON
- Default encryption: SSE-KMS (your KMS key ARN)

Bucket policy (enforce TLS + KMS):

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::YOUR_BUCKET",
        "arn:aws:s3:::YOUR_BUCKET/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    },
    {
      "Sid": "DenyUnencryptedUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::YOUR_BUCKET/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "aws:kms"
        }
      }
    },
    {
      "Sid": "DenyWrongKmsKey",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::YOUR_BUCKET/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "YOUR_KMS_KEY_ARN"
        }
      }
    }
  ]
}

## AWS: Lambda /upload-init

Environment variables
- UPLOAD_BUCKET = woundcare-uploads
- KMS_KEY_ARN = your key ARN

Purpose
- Generates KMS data key
- Returns pre-signed PUT URL
- Returns plaintextKeyB64, encryptedKeyB64, ivB64

API Gateway (HTTP API)
- Route: POST /upload-init -> Lambda
- CORS: allow POST, OPTIONS and headers content-type, authorization

## EC2 Inference Server

We use server_app.py (in this repo) and run it as app.py on EC2.

Install (Amazon Linux 2023)

sudo dnf update -y
sudo dnf install -y python3 python3-pip git libxcb
python3 -m venv ~/venv
source ~/venv/bin/activate
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install fastapi uvicorn[standard] numpy pillow opencv-python-headless timm \
  segmentation-models-pytorch boto3 cryptography firebase-admin python-multipart

Model files
Upload these to EC2 (example /home/ssm-user/woundcare/models):
- seg_best.pth
- cls_best.pth
- cls_pred_ft_best.pth

Server file
Copy server_app.py from this repo to EC2 as /home/ssm-user/woundcare/app.py.

Service account key
Generate Firebase Admin SDK key and place on EC2:
/home/ssm-user/woundcare/firebase-service-account.json

Environment file
Create /etc/woundcare.env:

UPLOAD_BUCKET=woundcare-uploads
MODEL_DIR=/home/ssm-user/woundcare/models
SEG_CKPT=seg_best.pth
CLS_BASE_CKPT=cls_best.pth
CLS_PRED_CKPT=cls_pred_ft_best.pth
CLS_MODE=gated
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
FIREBASE_CREDENTIALS=/home/ssm-user/woundcare/firebase-service-account.json
AUTH_ENABLED=true

systemd service

sudo tee /etc/systemd/system/woundcare.service >/dev/null <<'EOF'
[Unit]
Description=WoundCare AI FastAPI Server
After=network.target

[Service]
Type=simple
User=ssm-user
WorkingDirectory=/home/ssm-user/woundcare
EnvironmentFile=/etc/woundcare.env
ExecStart=/home/ssm-user/venv/bin/uvicorn app:app --host 0.0.0.0 --port 7860
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now woundcare.service

## API Endpoints

EC2 (FastAPI)
- GET /health
- POST /infer (auth required)
- POST /download-url (auth required)

API Gateway
- POST /upload-init

## Testing

Upload init (from PC)

$body = @{ contentType = "image/jpeg"; ext = "jpg" } | ConvertTo-Json
Invoke-RestMethod -Uri "https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/upload-init" \
  -Method POST -ContentType "application/json" -Body $body

Infer (from PC)

$body = @{
  s3Key = "uploads/....jpg"
  encryptedKeyB64 = "..."
  ivB64 = "..."
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://34.195.129.250:7860/infer" \
  -Method POST -ContentType "application/json" -Body $body

## Troubleshooting

S3 PUT 400 (SSE-KMS requires SigV4)
- Ensure Lambda uses SigV4 presigned URLs.

EC2 FastAPI fails with firebase_admin not found

source ~/venv/bin/activate
pip install firebase-admin
sudo systemctl restart woundcare.service

NoRegionError in boto3
- Set AWS_REGION and AWS_DEFAULT_REGION in /etc/woundcare.env.

Android clear-text HTTP error
- If using HTTP, set android:usesCleartextTraffic="true" in
  android/app/src/main/AndroidManifest.xml

## Files Added/Updated in Repo

- lib/screens/login_screen.dart
- lib/services/auth_service.dart
- lib/screens/capture_screen.dart
- lib/screens/analysis_screen.dart
- lib/utils/constants.dart
- server_app.py

## Security Notes

- Images are encrypted client-side (AES-GCM).
- S3 enforces SSE-KMS and TLS.
- Only store non-PHI in Firestore.
- Firebase Admin SDK key must remain private.
