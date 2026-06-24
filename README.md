# OpenWRT Node Packages — GitHub Actions Build

This repository contains a GitHub Actions workflow that builds **all Node.js packages** from the [nxhack/openwrt-node-packages](https://github.com/nxhack/openwrt-node-packages) feed for **OpenWRT 24.10.6** on **mediatek/filogic** (`aarch64_cortex-a53`).

## How it works

The workflow runs on `ubuntu-latest` and manually downloads the OpenWRT SDK for mediatek/filogic 24.10.6, then builds all node packages. It:

1. Installs build dependencies (compilers, python, etc.)
2. Downloads the official OpenWRT SDK from `downloads.openwrt.org`
3. Configures the custom node feed
4. Builds each package individually with `IGNORE_ERRORS=1`
5. Generates a `Packages.gz` index and signs it
6. Publishes the repository to **GitHub Pages**
7. Uploads built `.ipk` files and build logs as artifacts

## Usage

### Trigger a build

- **On push**: Pushing to `main` or `master` automatically triggers the workflow.
- **Manually**: Go to your repository's **Actions** tab, select **Build OpenWRT Node Packages**, and click **Run workflow**.

### Download packages

After a successful build, you have three ways to access the packages:

1. **GitHub Pages feed** (once configured — see below)
2. **Artifacts**: Download `ipk-packages-aarch64_cortex-a53.zip` from the workflow run page
3. **Build logs**: Download `build-logs.zip` to troubleshoot any failures

## Configuring GitHub Pages

After the first successful workflow run:

1. Go to repository **Settings → Pages**
2. Under **Source**, select **Deploy from a branch**
3. Set **Branch** to `gh-pages` / `/ (root)`
4. Click **Save**

## Adding the feed to your router

Once Pages is set up, add this line to `/etc/opkg/customfeeds.conf` on your OpenWRT router:

```
src/gz custom_node https://YOUR_USERNAME.github.io/YOUR_REPO/packages/aarch64_cortex-a53/node
```

Replace `YOUR_USERNAME` and `YOUR_REPO` with your GitHub username and repository name.

Then install the package signing key (required if `option check_signature 1` is set in `/etc/opkg.conf`):

```bash
# Download and install the public key
FINGERPRINT=$(wget -qO- https://YOUR_USERNAME.github.io/YOUR_REPO/packages/aarch64_cortex-a53/key-build.pub | \
  usign -F -p /dev/stdin)
wget -qO /etc/opkg/keys/$FINGERPRINT \
  https://YOUR_USERNAME.github.io/YOUR_REPO/packages/aarch64_cortex-a53/key-build.pub
```

Replace `YOUR_USERNAME` and `YOUR_REPO` with your GitHub username and repository name.

Then update and install:

```bash
opkg update
opkg list | grep node # see available node packages
opkg install node node-npm # example
```

## Packages built

The feed includes many Node.js-related packages:
- `node` — Node.js runtime
- `node-npm` — npm package manager
- `node-yarn` — Yarn package manager
- Various Node.js modules and tools

See the [nxhack/openwrt-node-packages](https://github.com/nxhack/openwrt-node-packages) repository for the full list.

## Workflow file

The build workflow is at `.github/workflows/build.yml`. Key details:

- **Runner**: `ubuntu-latest` (no container — fresh Ubuntu with modern glibc/gcc for Node.js 22 support)
- **SDK**: Downloaded fresh from `downloads.openwrt.org/releases/24.10.6/targets/mediatek/filogic/`
- **Feed**: `https://github.com/nxhack/openwrt-node-packages.git` (branch `openwrt-24.10`)
- **Build**: Per-package loop with `IGNORE_ERRORS=1` and `CONFIG_AUTOREMOVE=y`
- **Index**: `Packages.gz` generated for opkg compatibility
- **Deploy**: GitHub Pages via `peaceiris/actions-gh-pages@v3`

## Notes

- Build can take **1+ hours** depending on the number of packages
- `IGNORE_ERRORS=1` ensures the build continues even if some packages fail
- Only the `aarch64_cortex-a53` architecture is built (mediatek/filogic)
- Package signing is enabled (automatic via `usign` + SDK-generated `key-build`)
