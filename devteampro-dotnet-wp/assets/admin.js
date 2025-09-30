(function ($) {
  $(function () {
    $("#dtpPing").on("click", function (e) {
      e.preventDefault();
      var $out = $("#dtpPingResult").text(
        "<?php /* translators: loading */ ?>Loading..."
      );
      $.post(
        dtpAdmin.ajaxUrl,
        { action: "dtp_ping", _ajax_nonce: dtpAdmin.nonce },
        function (res) {
          if (res && res.success) {
            $out.text(res.data.now + (res.data.debug ? " (debug on)" : ""));
          } else {
            $out.text("Failed");
          }
        }
      ).fail(function (xhr) {
        $out.text("Error " + xhr.status);
      });
    });

    $("#dtp-settings-form").on("submit", function (e) {
      e.preventDefault();
      let data = $(this).serialize();
      $.ajax({
        url: dtpAdmin.ajaxUrl,
        method: "POST",
        data: {
          action: "dtp_settings_submit",
          formData: data,
          _ajax_nonce: dtpAdmin.nonce,
        },
        beforeSend: function () {
          Swal.fire({
            title: "Saving...",
            allowOutsideClick: false,
            didOpen: () => {
              Swal.showLoading();
            },
          });
        },
        success: function (response) {
          console.log(response);
          if (response.success) {
            Swal.fire({
              title: "Success",
              text: response.data.message,
              icon: "success",
              showConfirmButton: false,
              timer: 2000,
              allowOutsideClick: false,
              willClose: () =>{
                location.reload();
              }
            });
          } else {
            console.log("Error: " + response.data.message);
          }
        },
        error: function (xhr, status, error) {
          alert("AJAX Error: " + status);
        },
      });
    });

    $("#dtp-import-form").on("submit", function (e) {
      e.preventDefault();

      // Get the selected checkboxes
      var selectedImports = {};
      $('#dtp-import-form input[type="checkbox"]:checked').each(function () {
        selectedImports[$(this).attr("name")] = $(this).val();
        selectedImports[$(this).attr("name") + "_url"] = $(this).data("url");
      });

      // Send AJAX request
      $.ajax({
        url: dtpAdmin.ajaxUrl,
        method: "POST",
        data: {
          action: "dtp_start_import",
          _ajax_nonce: dtpAdmin.nonce,
          selected_imports: selectedImports,
        },
        beforeSend: function () {
          Swal.fire({
            title: "Importing...",
            allowOutsideClick: false,
            didOpen: () => {
              Swal.showLoading();
            },
          });
        },
        success: function (response) {
          if (response.success) {
            Swal.fire({
              title: "Import Completed",
              html: response.data.message,
              icon: "success",
              showConfirmButton: false,
              timer: 2500,
              allowOutsideClick: false,
            });
          } else {
            Swal.fire({
              title: "Import Failed",
              text: response.data.message,
              icon: "error",
              allowOutsideClick: false,
            });
          }
        },
        error: function (xhr, status, error) {
          $("#import-result").html(
            "<p>Status: " + status + "Error:" + error + "</p>"
          );
        },
      });
    });
  });
})(jQuery);
