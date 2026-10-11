# ML pipeline container

Build from the repository root and run with the local environment file:

```sh
docker build -f ml_pipeline/Dockerfile -t retailflow-ml .
docker run --rm --env-file ml_pipeline/.env retailflow-ml
```

The container runs enrichment followed by forecasting and publishing. Configure the
Supabase URL/key and optional weather key in `ml_pipeline/.env`; never put the
service role key in that file. This image uses Python 3.14, matching the pinned
dependency verification environment and the ML GitHub Actions job.

`murali_fruits_ml` is an application, so `pubspec.lock` should be committed to
keep Flutter builds reproducible. It is currently ignored by the repository's
root `.gitignore`; that file was left unchanged, and Flutter was unavailable here
to generate the lockfile.
