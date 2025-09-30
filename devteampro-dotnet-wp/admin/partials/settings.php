<!-- admin/partials/settings.php -->
<?php if (!defined('ABSPATH')) exit;

$token = esc_html(get_option('dtp_plugin_api_token', ''));
?>
<div class="wrap">
        <h1>DevTeamPro <span>Settings</span></h1>
</div>
<div class="wrap-body">
        <form id="dtp-settings-form">
                <div class="form-group">
                        <label for="email">Email</label>
                        <input type="email" class="form-control" id="email" name="email" value="<?php echo esc_attr(get_option('dtp_email', '')); ?>" />
                </div>
                <div class="form-group">
                        <label for="password">Password</label>
                        <input type="password" class="form-control" id="password" name="password" value="<?php echo esc_attr(get_option('dtp_password', '')); ?>" />
                </div>
                <div class="form-group">
                        <label for="organization-id">Organization ID</label>
                        <input type="number" name="organization_id" id="organization-id" value="<?php echo esc_attr(get_option('dtp_organization_id', '')); ?>" />
                </div>
                <div class="form-group">
                        <button type="submit">Save Settings</button>
                </div>
        </form>

        <?php
        if (!empty($token)):
        ?>
                <form id="dtp-import-form">
                        <div class="form-group">
                                <label><input type="checkbox" data-url="https://itapi.api97.com/api/PageApi/GetProgramIndexPage?organizationId" name="import_programs" value="programs" /> Import Programs</label>
                        </div>
                        <div class="form-group">
                                <label><input type="checkbox" data-url="https://itapi.api97.com/api/PageApi/GetPeopleIndexPage?organizationId" name="import_instructors" value="instructors" /> Import Instructors</label>
                        </div>
                        <div class="form-group">
                                <button type="submit" class="button-primary">Start Import</button>
                        </div>
                </form>
                <div id="import-result"></div>
        <?php endif; ?>
</div>