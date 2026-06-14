{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Force the loader to fetch CanvasKit locally from the local server rather than the Google gstatic CDN.
    canvasKitBaseUrl: "canvaskit/",
  },
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
  }
});
