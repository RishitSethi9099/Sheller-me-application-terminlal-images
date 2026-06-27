# Sheller VM Image Builder

This repository creates and publishes the Linux images used by the Sheller.me
Windows desktop application.

The pipeline produces:

- `ubuntu-22.04-minimal.qcow2`
- `kali-minimal.qcow2`
- `SHA256SUMS`
- `sheller-image-urls.env`

Ubuntu is based on Canonical's released Ubuntu 22.04 minimal cloud image. Kali
is based on Kali's current official QEMU image. The build then:

1. Creates the required `user` account with password `sheller`.
2. Enables SSH password authentication.
3. Grants passwordless sudo to the Sheller user.
4. Installs an idempotent service that formats and mounts `/dev/vdb` at
   `/home/user`.
5. Removes machine-specific SSH keys and state.
6. Compresses and checks both QCOW2 images.
7. Boots each image twice with 512 MB RAM and one CPU.
8. Proves SSH works and `/home/user` persists across the reboot.
9. Publishes the tested files to a stable GitHub Release.

## Run the pipeline

1. Open this repository on GitHub.
2. Select **Actions**.
3. Select **Build and release Sheller VM images**.
4. Click **Run workflow**.
5. Keep the release tag as `vm-images`.

The workflow can take a while because Kali's official QEMU image is large.

When it succeeds, open the `vm-images` release and copy the contents of
`sheller-image-urls.env` into the desktop application's `.env` file. For this
repository, the resulting configuration is:

```dotenv
SHELLER_UBUNTU_IMAGE_URL=https://github.com/RishitSethi9099/Sheller.me-application/releases/download/vm-images/ubuntu-22.04-minimal.qcow2
SHELLER_KALI_IMAGE_URL=https://github.com/RishitSethi9099/Sheller.me-application/releases/download/vm-images/kali-minimal.qcow2
```

Rebuild the desktop app after adding those values. Its environment manager will
then enable Ubuntu and Kali downloads.

## Optional base-image overrides

The manual workflow form accepts optional Ubuntu and Kali URLs. Leave them
blank to use the current official upstream sources. Overrides are still checked
against the `SHA256SUMS` file in the same upstream directory.

## Notes

- The public images intentionally use the application contract
  `user` / `sheller`; this is not a secret.
- GitHub Actions must have permission to create releases. The workflow requests
  `contents: write`.
- If a future Kali image exceeds GitHub's runner disk or release asset limits,
  run the same workflow on a larger self-hosted Linux runner.
