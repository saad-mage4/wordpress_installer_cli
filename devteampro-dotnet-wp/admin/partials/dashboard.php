<?php if (!defined('ABSPATH')) exit; ?>
<div class="wrap">
  <h1><?php esc_html_e('DevTeamPro', 'devteampro-dotnet-wp'); ?> <span><?php esc_html_e('.NET to Wordpress Migration', 'devteampro-dotnet-wp') ?></span></h1>
</div>

<div class="wrap-body">
  <p><?php esc_html_e('Welcome! Use the links below to navigate.', 'devteampro-dotnet-wp'); ?></p>

  <p>
    <a class="button button-primary" href="<?php echo esc_url(admin_url('admin.php?page=dtp-settings')); ?>">
      <?php esc_html_e('Go to Settings', 'devteampro-dotnet-wp'); ?>
    </a>
    <a class="button" href="<?php echo esc_url(admin_url('admin.php?page=dtp-docs')); ?>">
      <?php esc_html_e('View Documentation', 'devteampro-dotnet-wp'); ?>
    </a>
  </p>

  <hr />

  <p>
    <button id="dtpPing" class="button"><?php esc_html_e('Test AJAX Ping', 'devteampro-dotnet-wp'); ?></button>
    <span id="dtpPingResult" style="margin-left:8px;"></span>
  </p>
</div>