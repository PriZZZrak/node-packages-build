# OpenWRT Node Packages - GitHub Actions Build

This repository contains a GitHub Actions workflow that builds **Node.js packages** from the [nxhack/openwrt-node-packages](https://github.com/nxhack/openwrt-node-packages) feed for **OpenWRT 24.10.6** on **mediatek/filogic** (`aarch64_cortex-a53`).

The workflow produces a signed opkg repository published to GitHub Pages, ready to add as a custom feed on your router.

## How it works

The workflow runs on `ubuntu-latest` and manually downloads the OpenWRT SDK for mediatek/filogic 24.10.6, then builds all node packages. It:

1. Installs build dependencies (compilers, python, etc.)
2. Downloads the official OpenWRT SDK from `downloads.openwrt.org`
3. Configures the custom node feed
4. Builds each package individually with `IGNORE_ERRORS=1`
5. Generates a `Packages.gz` index and signs it
6. Removes non-node subfeeds (base, luci, packages, routing, telephony, already available in official OpenWRT repos)
7. Publishes only the `node/` subfeed to **GitHub Pages**
8. Uploads built `.ipk` files and build logs as artifacts

## Usage

### Trigger a build

- **On push**: Pushing to `main` or `master` automatically triggers the workflow.
- **Manually**: Go to your repository's **Actions** tab, select **Build OpenWRT Node Packages**, and click **Run workflow**.

### Download packages

After a successful build, you have three ways to access the packages:

1. **GitHub Pages feed** (once configured, see below)
2. **Artifacts**: Download `ipk-packages-aarch64_cortex-a53.zip` from the workflow run page
3. **Build logs**: Download `build-logs.zip` to troubleshoot any failures

## Configuring GitHub Pages

After the first successful workflow run:

1. Go to repository **Settings → Pages**
2. Under **Source**, select **Deploy from a branch**
3. Set **Branch** to `gh-pages` / `/ (root)`
4. Click **Save**

## Adding the feed to your router

### Recommended: setup-feed.sh

The repository includes `setup-feed.sh`, a convenience script that handles everything automatically:

```bash
wget -qO- https://raw.githubusercontent.com/YOUR_USERNAME/REPO/main/setup-feed.sh | sh
```

The script downloads the public signing key, extracts its fingerprint, installs it to `/etc/opkg/keys/`, and runs `opkg update`.

### Manual method

Add this line to `/etc/opkg/customfeeds.conf`:

```
src/gz custom_node https://YOUR_USERNAME.github.io/REPO/packages/aarch64_cortex-a53/node
```

Replace `YOUR_USERNAME` and `REPO` with your GitHub username and repository name.

Then install the package signing key (required if `option check_signature 1` is set in `/etc/opkg.conf`):

```bash
# Download and install the public key
FINGERPRINT=$(wget -qO- https://YOUR_USERNAME.github.io/REPO/packages/aarch64_cortex-a53/key-build.pub | \
  usign -F -p /dev/stdin)
wget -qO /etc/opkg/keys/$FINGERPRINT \
  https://YOUR_USERNAME.github.io/REPO/packages/aarch64_cortex-a53/key-build.pub
```

Then update and install:

```bash
opkg update
opkg list | grep node
opkg install node node-npm
```

## Packages built

The feed includes about 150 Node.js-related packages, with roughly 110 building successfully. Common packages:

- `node`, Node.js runtime (v22, Active LTS)
- `node-npm`, npm package manager
- `node-yarn`, Yarn package manager
- Various Node.js modules and tools

See the [nxhack/openwrt-node-packages](https://github.com/nxhack/openwrt-node-packages) repository for the full list.

## Workflow file

The build workflow is at `.github/workflows/build.yml`. Key details:

- **Runner**: `ubuntu-latest` (no container, fresh Ubuntu with modern glibc/gcc for Node.js 22 support)
- **Timeout**: 480 minutes (8 hours)
- **SDK**: Downloaded fresh from `downloads.openwrt.org/releases/24.10.6/targets/mediatek/filogic/`
- **Feed**: `https://github.com/nxhack/openwrt-node-packages.git` (branch — `openwrt-24.10`)
- **Node.js version**: `CONFIG_NODEJS_22=y` (Active LTS)
- **Build**: Per-package loop with `IGNORE_ERRORS=1` and `CONFIG_AUTOREMOVE=y`
- **Index**: `Packages.gz` generated, signed with `usign`, public key published alongside packages
- **Deploy**: Only the `node/` subfeed is deployed to GitHub Pages via `peaceiris/actions-gh-pages@v4`; other subfeeds are stripped
- **Signing**: Private signing key sourced from GitHub Secret `OPKG_SIGN_KEY`; public key `key-build.pub` is committed to the repository

## Notes

- Build can take **1+ hours** depending on how many packages are built
- `IGNORE_ERRORS=1` ensures the build continues even if some packages fail
- Only the `aarch64_cortex-a53` architecture is built (mediatek/filogic)
- Package signing is enabled. The public key (`key-build.pub`) is committed to the repo, the private key is stored as the `OPKG_SIGN_KEY` GitHub Secret
- Native C++ addons for aarch64 may fail to build due to node-gyp cross-compilation limitations
- Some packages are marked `@BROKEN` or `@NODEJS_24:BROKEN` in the upstream feed and are skipped
