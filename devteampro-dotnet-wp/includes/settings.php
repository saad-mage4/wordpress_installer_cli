<?php
if (!defined('ABSPATH')) exit;

add_action('admin_init', function () {
    register_setting(DTP_SETTINGS_GROUP, 'dtp_options', [
        'type'              => 'array',
        'sanitize_callback' => function ($input) {
            $out = get_option('dtp_options', []);
            $out['api_key']     = isset($input['api_key']) ? sanitize_text_field($input['api_key']) : '';
            $out['enable_logs'] = !empty($input['enable_logs']) ? 1 : 0;
            return $out;
        },
    ]);

    add_settings_section(
        'dtp_main_section',
        __('General Settings', 'devteampro-dotnet-wp'),
        function () {
            echo '<p>' . esc_html__('Configure your plugin settings below.', 'devteampro-dotnet-wp') . '</p>';
        },
        DTP_SETTINGS_GROUP
    );

    add_settings_field(
        'dtp_api_key',
        __('API Key', 'devteampro-dotnet-wp'),
        'dtp_field_api_key',
        DTP_SETTINGS_GROUP,
        'dtp_main_section'
    );

    add_settings_field(
        'dtp_enable_logs',
        __('Enable Logs', 'devteampro-dotnet-wp'),
        'dtp_field_enable_logs',
        DTP_SETTINGS_GROUP,
        'dtp_main_section'
    );
});

function dtp_field_api_key() {
    $opts = get_option('dtp_options', []);
    $val  = isset($opts['api_key']) ? $opts['api_key'] : '';
    echo '<input type="text" name="dtp_options[api_key]" value="' . esc_attr($val) . '" class="regular-text" />';
}

function dtp_field_enable_logs() {
    $opts = get_option('dtp_options', []);
    $checked = !empty($opts['enable_logs']) ? 'checked' : '';
    echo '<label><input type="checkbox" name="dtp_options[enable_logs]" value="1" ' . $checked . ' /> ' .
         esc_html__('Write debug logs (wp-content/debug.log)', 'devteampro-dotnet-wp') .
         '</label>';
}
