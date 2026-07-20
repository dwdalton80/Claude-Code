# Apple Root CA certificates

`verifyStoreKit2Transaction` in `functions/src/index.ts` loads every `.cer`
file in this directory at first use and hands them to Apple's
`SignedDataVerifier` as the trusted root certificate chain for validating
StoreKit 2 signed transaction JWTs.

## Setup (one-time, before first deploy)

Download Apple's root CA certificate from
https://www.apple.com/certificateauthority/ and place it here:

```bash
cd ~/Claude-Code/studyfire/functions/certs
curl -o AppleRootCA-G3.cer https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
```

This file is binary (DER-encoded X.509) and safe to commit — it's a public
certificate, not a secret.

## Why this exists

StoreKit 2 (the default in `in_app_purchase_storekit` v0.4.x+ on iOS 15+)
signs transactions as a JWS, not the old base64 App Store receipt. Verifying
that JWS means checking its signature chain against Apple's own root CA,
which is what `SignedDataVerifier` does using the cert(s) in this folder.
