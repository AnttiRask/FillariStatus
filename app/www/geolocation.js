// navigator.geolocation -> Shiny inputs `user_location` / `location_error`.
// The position is read when the page connects and again whenever the user taps
// "Update my location" (a bike ride changes it; the station data refreshes on
// its own every minute).
(function () {
  function send(name, value) {
    Shiny.setInputValue(name, value, { priority: "event" });
  }

  // `fresh` skips the browser's cached position, so a manual update really
  // re-reads it. `done(ok)` runs when the request finishes.
  function locate(fresh, done) {
    if (!navigator.geolocation) {
      send("location_error", { code: 0 });
      if (done) done(false);
      return;
    }
    navigator.geolocation.getCurrentPosition(
      function (p) {
        send("user_location", {
          lat: p.coords.latitude,
          lon: p.coords.longitude,
          accuracy: p.coords.accuracy
        });
        if (done) done(true);
      },
      function (e) {
        send("location_error", { code: e.code });
        if (done) done(false);
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: fresh ? 0 : 30000 }
    );
  }

  $(document).on("shiny:connected", function () {
    locate(false);
  });

  // Shiny's actionLink counts clicks; this also does the actual work. The link
  // text shows progress and failure (strings come from data attributes).
  $(document).on("click", "#update_location", function () {
    var link = this;
    if (link.dataset.working) return;
    var label = link.textContent;
    link.dataset.working = "1";
    link.textContent = link.dataset.busy;
    locate(true, function (ok) {
      if (ok) {
        link.textContent = label;
        delete link.dataset.working;
      } else {
        link.textContent = link.dataset.failed;
        setTimeout(function () {
          link.textContent = label;
          delete link.dataset.working;
        }, 4000);
      }
    });
  });
})();
