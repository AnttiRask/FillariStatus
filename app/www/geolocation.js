// navigator.geolocation -> Shiny inputs `user_location` / `location_error`.
// The position is read once, when the page connects; to refresh it, reload.
(function () {
  function send(name, value) {
    Shiny.setInputValue(name, value, { priority: "event" });
  }

  function locate() {
    if (!navigator.geolocation) {
      send("location_error", { code: 0 });
      return;
    }
    navigator.geolocation.getCurrentPosition(
      function (p) {
        send("user_location", {
          lat: p.coords.latitude,
          lon: p.coords.longitude,
          accuracy: p.coords.accuracy
        });
      },
      function (e) {
        send("location_error", { code: e.code });
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 30000 }
    );
  }

  $(document).on("shiny:connected", locate);
})();
