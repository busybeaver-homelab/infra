# Application Build & Packaging Workflow (`/apps`)

This directory contains applications, services, and configurations that are deployed onto the Cloud or Homelab infrastructure.

## Packaging Process

To maintain a clean separation of concerns, the build process is handled inside GitHub Actions (via the `.github/workflows/build-apps.yml` workflow):

1. **Build Step:** Any compilers, bundlers, or test suites are run inside the `apps/<app-name>` directories.
2. **Packaging Step:** The applications are bundled and compressed into standard `.zip` or `.tar.gz` packages inside the `/dist` directory.
3. **Artifact Upload:** These packaged zip archives are uploaded as GitHub Actions artifacts.
4. **Infrastructure Deployment:** When OpenTofu runs, it can reference and download the packages from `/dist/` to upload them to Google Cloud Storage, Cloud Functions, Cloud Run, or target servers via Ansible.

## Standard output `/dist/`

The `/dist/` directory is automatically ignored by Git (configured in `.gitignore`) so built assets are never committed to version control. They are solely generated on demand during local development or via the CI runner.
