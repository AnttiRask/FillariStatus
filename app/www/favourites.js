// Favourite station IDs: localStorage <-> Shiny input `favourites`.
// Storage can be unavailable (private windows, blocked site data), so every
// access is wrapped; favourites then last for the current page only.
(function () {
  var KEY = "fillaristatus.favourites";

  function read() {
    try {
      var v = JSON.parse(localStorage.getItem(KEY));
      return Array.isArray(v) ? v : [];
    } catch (e) {
      return [];
    }
  }

  function write(list) {
    try {
      localStorage.setItem(KEY, JSON.stringify(list));
    } catch (e) {}
  }

  var current = read();

  function publish() {
    Shiny.setInputValue("favourites", current, { priority: "event" });
  }

  // Toggling a favourite redraws the map markers, which closes an open popup.
  // Re-open the popup for this station once the redraw has finished. Leaflet
  // fires `layeradd` before the popups are bound to the new markers, so wait
  // for the burst of layeradd events to settle and then look the marker up.
  function reopenPopupFor(id) {
    var widget = window.HTMLWidgets && HTMLWidgets.find("#map");
    var map = widget && widget.getMap && widget.getMap();
    if (!map) return;

    var needle = 'data-station-id="' + id + '"';
    var settle;
    var giveUp;

    function done() {
      map.off("layeradd", onAdd);
      clearTimeout(settle);
      clearTimeout(giveUp);
    }

    function scan() {
      map.eachLayer(function (layer) {
        var popup = layer.getPopup && layer.getPopup();
        var content = popup && popup.getContent();
        if (typeof content === "string" && content.indexOf(needle) !== -1) {
          layer.openPopup();
          done();
        }
      });
    }

    function onAdd() {
      clearTimeout(settle);
      settle = setTimeout(scan, 60);
    }

    map.on("layeradd", onAdd);
    giveUp = setTimeout(done, 3000);
  }

  $(document).on("shiny:connected", publish);

  // Capture phase: Leaflet stops click propagation inside popups, so a normal
  // (bubbling) document listener would never see clicks on a popup's star.
  document.addEventListener(
    "click",
    function (e) {
      var btn = e.target.closest && e.target.closest(".fs-fav");
      if (!btn) return;

      var id = btn.getAttribute("data-station-id");
      var i = current.indexOf(id);
      if (i === -1) {
        current.push(id);
      } else {
        current.splice(i, 1);
      }
      write(current);

      if (btn.closest(".leaflet-popup")) reopenPopupFor(id);
      publish();
    },
    true
  );
})();
