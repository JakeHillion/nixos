# ca

Getting the certificates in the right place is a manual process (for now, at least). This is to keep the most control over the root certificate's key and allow manual cycling. The manual commands should be run on a trusted machine.

Creating a 10 year root certificate:

    nix run nixpkgs#step-cli -- certificate create 'Hillion ACME' cert.pem key.pem --kty=EC --curve=P-521 --profile=root-ca --not-after=87600h

Creating the intermediate key:

    nix run nixpkgs#step-cli -- certificate create 'Hillion ACME (sodium.pop.neb.jakehillion.me)' intermediate_cert.pem intermediate_key.pem --kty=EC --curve=P-521 --profile=intermediate-ca --not-after=8760h --ca=$NIXOS_ROOT/modules/ca/cert.pem --ca-key=DOWNLOADED_KEY.pem
