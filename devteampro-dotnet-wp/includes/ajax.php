<?php
if (!defined('ABSPATH')) exit;

/**
 * Example admin AJAX: test connectivity
 * JS: jQuery.post(dtpAdmin.ajaxUrl, { action:'dtp_ping', _ajax_nonce: dtpAdmin.nonce }, cb)
 */
add_action('wp_ajax_dtp_ping', function () {
    check_ajax_referer('dtp_admin_nonce');
    if (!current_user_can('manage_options')) wp_send_json_error(['message' => 'forbidden'], 403);

    wp_send_json_success([
        'now'   => current_time('mysql'),
        'debug' => !empty(get_option('dtp_options', [])['enable_logs']),
    ]);
});


add_action('wp_ajax_dtp_settings_submit', function () {
    check_ajax_referer('dtp_admin_nonce');
    if (!current_user_can('manage_options')) wp_send_json_error(['message' => 'forbidden'], 403);

    $formData = [];
    parse_str($_POST['formData'] ?? '', $formData);
    if (empty($formData)) {
        wp_send_json_error(['message' => 'no data'], 400);
    }

    // Get the email and password from the form submission
    $email = sanitize_email($formData['email']);
    $password = sanitize_text_field($formData['password']);
    $organization_id = sanitize_text_field($formData['organization_id']);

    update_option('dtp_email', $email);
    update_option('dtp_password', $password);
    update_option('dtp_organization_id', $organization_id);


    // Send the API request to get the token
    $token = your_plugin_generate_and_save_token($email, $password);

    if ($token) {
        wp_send_json_success(array('message' => 'Token generated successfully', 'token' => $token));
    } else {
        wp_send_json_error(array('message' => 'Failed to generate token'));
    }
});

/**
 * Start import process based on selected options
 * JS: jQuery.post(dtpAdmin.ajaxUrl, { action:'dtp_start_import', selected_imports: {...}, _ajax_nonce: dtpAdmin.nonce }, cb)
 *
add_action('wp_ajax_dtp_start_import', function () {
    check_ajax_referer('dtp_admin_nonce');  // Verify nonce
    if (!current_user_can('administrator')) wp_send_json_error(['message' => 'Unauthorized'], 403); // Check user permissions

    $selected_imports = isset($_POST['selected_imports']) ? $_POST['selected_imports'] : [];

    $message = 'Import process completed successfully. <br>';
    $imported_program = 0;
    $updated_program = 0;
    // instructors
    $imported_instructor = 0;
    $updated_instructor = 0;
    $menu_items = array();

    // Trigger imports based on selected checkboxes
    if (isset($selected_imports['import_programs'])) {
        // Import programs if "import_programs" checkbox is selected
        $token = get_option('dtp_plugin_api_token', '');
        $organization_id = get_option('dtp_organization_id', '');
        $api_url = isset($selected_imports['import_programs_url']) ? esc_url_raw($selected_imports['import_programs_url']) : '';
        if (empty($token) || empty($organization_id)) {
            wp_send_json_error(['message' => 'Token or Organization ID is missing. Please check your settings.']);
        }
        $result = my_import_programs_via_curl($token, $organization_id, $api_url);
        $imported_program += $result['imported'];
        $updated_program += $result['updated'];
        $menu_items[] = $result['menu_item'];

        $message .= "Programs Imported: $imported_program, Updated: $updated_program. <br>";
    }

    if (isset($selected_imports['import_instructors'])) {
        // Import programs if "import_programs" checkbox is selected
        $token = get_option('dtp_plugin_api_token', '');
        $organization_id = get_option('dtp_organization_id', '');
        $api_url = isset($selected_imports['import_instructors_url']) ? esc_url_raw($selected_imports['import_instructors_url']) : '';
        if (empty($token) || empty($organization_id)) {
            wp_send_json_error(['message' => 'Token or Organization ID is missing. Please check your settings.']);
        }
        $result = my_import_instructors_via_curl($token, $organization_id, $api_url);
        $imported_instructor += $result['imported'];
        $updated_instructor += $result['updated'];
        $menu_items[] = $result['menu_item'];
        $message .= "Instructors Imported: $imported_instructor, Updated: $updated_instructor. ";
    }

    // $result = my_import_instructors_via_curl($token, $organization_id, $api_url);
    // You can add more imports based on checkboxes here (e.g., import images, etc.)

    if ($imported_program > 0 || $imported_instructor > 0 || $updated_program > 0 || $updated_instructor > 0) {;

        
        // === Add a real menu item to the "Main Menu" ===
        $menu_name  = 'Main Menu';
        $menu_link  = 'https://example.com';   // <-- change this
        $menu_label = 'My Link';               // <-- change this

        $menu_obj = wp_get_nav_menu_object($menu_name);
        if (!$menu_obj) {
            // Optional: create the menu if it doesn't exist
            $menu_id = wp_create_nav_menu($menu_name);
        } else {
            $menu_id = $menu_obj->term_id;
        }

        // Avoid duplicates: check if an item with same URL already exists
        $exists = false;
        if ($menu_id) {
            $items = wp_get_nav_menu_items($menu_id, ['post_status' => 'any']);
            if ($items) {
                foreach ($items as $item) {
                    if (!empty($item->url) && untrailingslashit($item->url) === untrailingslashit($menu_link)) {
                        $exists = true;
                        break;
                    }
                }
            }
        }

        if ($menu_id && !$exists) {
            wp_update_nav_menu_item($menu_id, 0, [
                'menu-item-title'  => $menu_label,
                'menu-item-url'    => esc_url_raw($menu_link),
                'menu-item-status' => 'publish',
                'menu-item-type'   => 'custom',
            ]);
            $message .= '<br>Menu item added to “Main Menu”.';
        } elseif ($exists) {
            $message .= '<br>Menu item already exists in “Main Menu”.';
        } else {
            $message .= '<br>Could not find or create “Main Menu”.';
        }

        wp_send_json_success(['message' => $message]);
    } else {
        wp_send_json_error(['message' => 'Nothing imported or updated.']);
    }
});
*/



add_action('wp_ajax_dtp_start_import', function () {
    check_ajax_referer('dtp_admin_nonce');  // Verify nonce
    if (!current_user_can('administrator')) {
        wp_send_json_error(['message' => 'Unauthorized'], 403);
    }

    $selected_imports = isset($_POST['selected_imports']) ? (array) $_POST['selected_imports'] : [];

    $message = 'Import process completed successfully. <br>';
    $imported_program = $updated_program = 0;
    $imported_instructor = $updated_instructor = 0;
    $menu_items = []; // we will collect menu items here

    // === Programs ===
    if (isset($selected_imports['import_programs'])) {
        $token = get_option('dtp_plugin_api_token', '');
        $organization_id = get_option('dtp_organization_id', '');
        $api_url = isset($selected_imports['import_programs_url']) ? esc_url_raw($selected_imports['import_programs_url']) : '';
        if (empty($token) || empty($organization_id)) {
            wp_send_json_error(['message' => 'Token or Organization ID is missing. Please check your settings.']);
        }

        $result = my_import_programs_via_curl($token, $organization_id, $api_url);
        $imported_program += intval($result['imported'] ?? 0);
        $updated_program  += intval($result['updated']  ?? 0);

        if (!empty($result['menu_item'])) {
            // allow string, array of strings, or structured arrays
            if (is_array($result['menu_item']) && isset($result['menu_item'][0])) {
                $menu_items = array_merge($menu_items, (array) $result['menu_item']);
            } else {
                $menu_items[] = $result['menu_item'];
            }
        }

        $message .= "Programs Imported: $imported_program, Updated: $updated_program. <br>";
    }

    // === Instructors ===
    if (isset($selected_imports['import_instructors'])) {
        $token = get_option('dtp_plugin_api_token', '');
        $organization_id = get_option('dtp_organization_id', '');
        $api_url = isset($selected_imports['import_instructors_url']) ? esc_url_raw($selected_imports['import_instructors_url']) : '';
        if (empty($token) || empty($organization_id)) {
            wp_send_json_error(['message' => 'Token or Organization ID is missing. Please check your settings.']);
        }

        $result = my_import_instructors_via_curl($token, $organization_id, $api_url);
        $imported_instructor += intval($result['imported'] ?? 0);
        $updated_instructor  += intval($result['updated']  ?? 0);

        if (!empty($result['menu_item'])) {
            if (is_array($result['menu_item']) && isset($result['menu_item'][0])) {
                $menu_items = array_merge($menu_items, (array) $result['menu_item']);
            } else {
                $menu_items[] = $result['menu_item'];
            }
        }

        $message .= "Instructors Imported: $imported_instructor, Updated: $updated_instructor. ";
    }

    // === If anything changed, update menu ===
    if ($imported_program > 0 || $updated_program > 0 || $imported_instructor > 0 || $updated_instructor > 0) {

        // Which menu to update
        $menu_name = 'Main Menu';

        $menu_obj = wp_get_nav_menu_object($menu_name);
        if (!$menu_obj) {
            $menu_id = wp_create_nav_menu($menu_name);
        } else {
            $menu_id = $menu_obj->term_id;
        }

        if (!$menu_id || is_wp_error($menu_id)) {
            wp_send_json_error(['message' => $message . '<br>Could not find or create “Main Menu”.']);
        }

        // Normalize -> Sanitize
        $normalized = [];
        foreach ((array) $menu_items as $raw) {
            $normalized = array_merge($normalized, dtp_normalize_menu_items($raw));
        }

        $clean_items = [];
        foreach ($normalized as $it) {
            $url   = isset($it['url']) ? esc_url_raw($it['url']) : '';
            $label = isset($it['label']) ? sanitize_text_field($it['label']) : '';
            if (!$url || !$label) continue;

            $clean_items[] = [
                'url'          => $url,
                'label'        => $label,
                // optional future fields if you ever add them:
                'parent_title' => isset($it['parent_title']) ? sanitize_text_field($it['parent_title']) : '',
                'parent_url'   => isset($it['parent_url']) ? esc_url_raw($it['parent_url']) : '',
                'classes'      => isset($it['classes']) ? sanitize_text_field($it['classes']) : '',
                'target'       => (isset($it['target']) && $it['target'] === '_blank') ? '_blank' : '',
                'attr_title'   => isset($it['attr_title']) ? sanitize_text_field($it['attr_title']) : '',
                'position'     => isset($it['position']) ? intval($it['position']) : 0,
            ];
        }

        if (empty($clean_items)) {
            wp_send_json_success(['message' => $message . '<br>No menu items to add/update.']);
        }

        // For duplicate checks and parent resolution
        $existing = wp_get_nav_menu_items($menu_id, ['post_status' => 'any']) ?: [];
        $by_url   = [];
        $by_title = [];
        foreach ($existing as $e) {
            $norm_url = $e->url ? untrailingslashit($e->url) : '';
            if ($norm_url) $by_url[$norm_url][] = $e;
            $by_title[trim(wp_specialchars_decode($e->title))][] = $e;
        }

        $added = 0; $updated = 0; $skipped = 0;

        foreach ($clean_items as $it) {
            // Resolve optional parent
            $parent_id = 0;
            if (!empty($it['parent_url'])) {
                $purl = untrailingslashit($it['parent_url']);
                if (isset($by_url[$purl])) $parent_id = (int) $by_url[$purl][0]->ID;
            } elseif (!empty($it['parent_title'])) {
                $ptitle = $it['parent_title'];
                if (isset($by_title[$ptitle])) $parent_id = (int) $by_title[$ptitle][0]->ID;
            }

            // Check duplicate: same URL under same parent
            $norm = untrailingslashit($it['url']);
            $existing_item = null;
            if (isset($by_url[$norm])) {
                foreach ($by_url[$norm] as $e) {
                    if ((int) $e->menu_item_parent === (int) $parent_id) {
                        $existing_item = $e;
                        break;
                    }
                }
            }

            if ($existing_item) {
                // Update title/props if changed
                $current_title = trim(wp_specialchars_decode($existing_item->title));
                $needs_update  = ($current_title !== $it['label']);
                if ($needs_update) {
                    wp_update_nav_menu_item($menu_id, $existing_item->ID, [
                        'menu-item-title'      => $it['label'],
                        'menu-item-url'        => $it['url'],
                        'menu-item-status'     => 'publish',
                        'menu-item-type'       => 'custom',
                        'menu-item-parent-id'  => $parent_id,
                        'menu-item-classes'    => $it['classes'],
                        'menu-item-target'     => $it['target'],
                        'menu-item-attr-title' => $it['attr_title'],
                        'menu-item-position'   => $it['position'],
                    ]);
                    $updated++;
                } else {
                    $skipped++;
                }
                continue;
            }

            // Create new item
            $new_id = wp_update_nav_menu_item($menu_id, 0, [
                'menu-item-title'      => $it['label'],
                'menu-item-url'        => $it['url'],
                'menu-item-status'     => 'publish',
                'menu-item-type'       => 'custom',
                'menu-item-parent-id'  => $parent_id,
                'menu-item-classes'    => $it['classes'],
                'menu-item-target'     => $it['target'],
                'menu-item-attr-title' => $it['attr_title'],
                'menu-item-position'   => $it['position'], // 0 => append to end
            ]);

            if (!is_wp_error($new_id) && $new_id) {
                $added++;
                // Update lookup tables so subsequent children can find this as parent
                $obj = get_post($new_id);
                if ($obj) {
                    $existing[] = $obj;
                    $by_title[$it['label']][] = (object) ['ID' => $new_id, 'title' => $it['label']];
                    $by_url[$norm][] = (object) ['ID' => $new_id, 'url' => $it['url'], 'menu_item_parent' => $parent_id];
                }
            }
        }

        $message .= sprintf('<br>Menu updates: added %d, updated %d, skipped %d.', $added, $updated, $skipped);
        wp_send_json_success(['message' => $message]);
    } else {
        wp_send_json_error(['message' => 'Nothing imported or updated.']);
    }
});