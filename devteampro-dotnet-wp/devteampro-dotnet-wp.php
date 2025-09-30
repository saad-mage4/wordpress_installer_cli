    <?php
    /**
     * Plugin Name: DevTeamPro .Net to Wordpress Importer
     * Description: A plugin to import .Net content into WordPress.
     * Version: 1.0
     * Author: DevTeamPro
     * Author URI: https://www.devteampro.com
     * License: GPL2
     */

    if (!defined('ABSPATH')) exit;

    /** Constants */
    define('DTP_PLUGIN_FILE', __FILE__);
    define('DTP_PLUGIN_DIR', plugin_dir_path(__FILE__));
    define('DTP_PLUGIN_URL', plugin_dir_url(__FILE__));
    define('DTP_MENU_SLUG', 'dtp');                 // top-level slug
    define('DTP_SETTINGS_GROUP', 'dtp_settings');   // Settings API group

    /** Autoload/Requires (logic only, no markup) */
    require_once DTP_PLUGIN_DIR . 'includes/settings.php'; // registers settings/fields
    require_once DTP_PLUGIN_DIR . 'includes/ajax.php';     // admin-ajax handlers

    /** Activation */
    register_activation_hook(__FILE__, function () {
        if (get_option('dtp_options') === false) {
            add_option('dtp_options', ['api_key' => '', 'enable_logs' => 0]);
        }
    });

    /** Admin menu (no markup here) */
    add_action('admin_menu', function () {
        $cap = 'manage_options';

        add_menu_page(
            __('DevTeamPro .NET', 'devteampro-dotnet-wp'),
            __('DevTeamPro', 'devteampro-dotnet-wp'),
            $cap,
            DTP_MENU_SLUG,
            function () {
                dtp_require_partial('dashboard');
            },
            'dashicons-admin-generic',
            56
        );

        add_submenu_page(
            DTP_MENU_SLUG,
            __('Settings', 'devteampro-dotnet-wp'),
            __('Settings', 'devteampro-dotnet-wp'),
            $cap,
            'dtp-settings',
            function () {
                dtp_require_partial('settings');
            }
        );

        add_submenu_page(
            DTP_MENU_SLUG,
            __('Documentation', 'devteampro-dotnet-wp'),
            __('Documentation', 'devteampro-dotnet-wp'),
            $cap,
            'dtp-docs',
            function () {
                dtp_require_partial('docs');
            }
        );
    });

    /** Helper to include a partial safely (content-only files) */
    function dtp_require_partial($name)
    {
        if (!current_user_can('manage_options')) return;
        $file = DTP_PLUGIN_DIR . "admin/partials/{$name}.php";
        if (file_exists($file)) {
            // Expose common data to partials:
            $dtp_options = get_option('dtp_options', []);
            $dtp_nonce   = wp_create_nonce('dtp_admin_nonce');
            require $file;
        } else {
            echo '<div class="wrap"><h1>Not found</h1><p>Partial missing: ' . esc_html($name) . '</p></div>';
        }
    }

    /** Enqueue admin assets only on our screens */
    add_action('admin_enqueue_scripts', function ($hook) {
        // Our screens contain these substrings:
        // 'toplevel_page_dtp', 'devteampro-dotnet-wp_page_dtp-settings', 'devteampro-dotnet-wp_page_dtp-docs'
        if (strpos($hook, 'dtp') === false) return;

        if (file_exists(DTP_PLUGIN_DIR . 'assets/admin.css')) {
            wp_enqueue_style('sweetalert2', 'https://cdn.jsdelivr.net/npm/sweetalert2@11/dist/sweetalert2.min.css', [], '11.0.0');
            wp_enqueue_style('dtp-admin', DTP_PLUGIN_URL . 'assets/admin.css', [], '0.1.0');
        }
        if (file_exists(DTP_PLUGIN_DIR . 'assets/admin.js')) {
            wp_enqueue_script('dtp-admin', DTP_PLUGIN_URL . 'assets/admin.js', ['jquery'], '0.1.0', true);
            wp_enqueue_script('sweetalert2', 'https://cdn.jsdelivr.net/npm/sweetalert2@11', [], '11.0.0', true);
            wp_localize_script('dtp-admin', 'dtpAdmin', [
                'ajaxUrl' => admin_url('admin-ajax.php'),
                'nonce'   => wp_create_nonce('dtp_admin_nonce'),
            ]);
        }
    });


    function your_plugin_generate_and_save_token($email, $password)
    {
        $url = 'https://itapi.api97.com/Token';

        // Prepare the body data for the POST request
        $body = array(
            'Email' => $email,
            'Password' => $password
        );

        // Convert body to URL encoded format
        $body = http_build_query($body);

        // Initialize cURL session
        $ch = curl_init();

        // Set cURL options
        curl_setopt($ch, CURLOPT_URL, $url);  // API URL
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);  // Return response as a string
        curl_setopt($ch, CURLOPT_POST, true);  // Send a POST request
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);  // Set POST fields (email and password)
        curl_setopt($ch, CURLOPT_HTTPHEADER, array(
            'Content-Type: application/x-www-form-urlencoded',  // Set the content type to form-urlencoded
            'Accept: application/json'  // Expect a JSON response
        ));

        // Execute the cURL request
        $response = curl_exec($ch);

        // Check for cURL errors
        if (curl_errno($ch)) {
            error_log('cURL Error: ' . curl_error($ch)); // Log the error
            curl_close($ch); // Close cURL session
            return false;
        }

        // Close the cURL session
        curl_close($ch);

        // Decode the JSON response
        $data = json_decode($response, true);

        // Check if we received a token in the response
        if (isset($data['token'])) {
            // Save the token in WordPress options table
            update_option('dtp_plugin_api_token', $data['token']);
            return $data['token']; // Return the token
        } else {
            // If no token is found, log the response data for debugging
            error_log('Token not found in the API response. Response Data: ' . print_r($data, true));
            return false; // Return false if the token is not found
        }
    }



    /**
     * Import programs from API
     */
    function my_import_programs_via_curl($token, $organization_id, $api_url)
    {
        $imageSiteUrl = "https://res.cloudinary.com/display97/image/upload/";
        $token = trim($token);
        $url   = $api_url . "=" . intval($organization_id);

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                "accept: text/plain",
                "Authorization: {$token}",
            ],
            CURLOPT_TIMEOUT => 30,
        ]);

        $response = curl_exec($ch);
        if ($response === false) {
            error_log('cURL error: ' . curl_error($ch));
            curl_close($ch);
            return ['ok' => false, 'imported' => 0, 'updated' => 0];
        }
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);


        if ($status >= 400) {
            error_log('API HTTP ' . $status . ': ' . substr($response, 0, 500));
            return ['ok' => false, 'imported' => 0, 'updated' => 0];
        }

        $data = json_decode($response, true);

        if (!is_array($data) || empty($data['programs'])) {
            error_log('Unexpected API format or no programs.');
            return ['ok' => false, 'imported' => 0, 'updated' => 0];
        }

        $imported = 0;
        $updated  = 0;
        $menu_item = 'programs';

        foreach ($data['programs'] as $program) {
            // Find existing post by API program ID
            $existing = get_posts([
                'post_type'      => 'programs',
                'meta_key'       => 'api_program_id',
                'meta_value'     => $program['id'],
                'posts_per_page' => 1,
                'post_status'    => 'any',
                'fields'         => 'ids',
            ]);

            $postarr = [
                'post_type'    => 'programs',
                'post_status'  => 'publish',
                'post_title'   => $program['name'] ?? 'Untitled Program',
                'post_excerpt' => $program['excerpt'] ?? '',
                // 🚫 Do NOT set post_content (we only store in ACF body_content)
            ];

            if (!empty($existing)) {
                $postarr['ID'] = $existing[0];
                $post_id = wp_update_post($postarr, true);
                if (!is_wp_error($post_id)) $updated++;
            } else {
                $post_id = wp_insert_post($postarr, true);
                if (!is_wp_error($post_id)) $imported++;
            }

            if (is_wp_error($post_id)) {
                error_log('Post error: ' . $post_id->get_error_message());
                continue;
            }

            if (!is_wp_error($post_id)) {
                // Featured Image
                if (!empty($program['excerptimagePath'])) {
                    $imgFullPath = $imageSiteUrl . $program['excerptimagePath'];
                    $image_id = my_import_image_to_media($imgFullPath, $post_id);
                    set_post_thumbnail($post_id, $image_id);
                }
            }

            // Process and replace images in body_content before saving
            $body_content = my_import_and_replace_images($program['bodyContent'] ?? '', $post_id);



            // Save ACF fields
            if (function_exists('update_field')) {
                update_field('api_program_id', $program['id'], $post_id);
                update_field('name',           $program['name'] ?? '',        $post_id);
                update_field('body_content',   $body_content,                 $post_id);
                update_field('excerpt',        $program['excerpt'] ?? '',     $post_id);
                update_field('rank',           $program['rank'] ?? '',        $post_id);
                update_field('active',         !empty($program['active']),    $post_id);
            } else {
                update_post_meta($post_id, 'api_program_id', $program['id']);
                update_post_meta($post_id, 'name',           $program['name'] ?? '');
                update_post_meta($post_id, 'body_content',   $body_content);
                update_post_meta($post_id, 'excerpt',        $program['excerpt'] ?? '');
                update_post_meta($post_id, 'rank',           $program['rank'] ?? '');
                update_post_meta($post_id, 'active',         !empty($program['active']) ? 1 : 0);
            }
        }

        return ['ok' => true, 'imported' => $imported, 'updated' => $updated, 'menu_item' => $menu_item];
    }

    /**
     * Import Instructors from API
     */
    function my_import_instructors_via_curl($token, $organization_id, $api_url)
    {
        $imageSiteUrl = "https://res.cloudinary.com/display97/image/upload/";
        $token = trim($token);
        $url   = $api_url . "=" . intval($organization_id);

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                "accept: text/plain",
                "Authorization: {$token}",
            ],
            CURLOPT_TIMEOUT => 30,
        ]);

        $response = curl_exec($ch);
        if ($response === false) {
            error_log('cURL error: ' . curl_error($ch));
            curl_close($ch);
            return ['ok' => false, 'imported' => 0, 'updated' => 0];
        }
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);


        if ($status >= 400) {
            error_log('API HTTP ' . $status . ': ' . substr($response, 0, 500));
            return ['ok' => false, 'imported' => 0, 'updated' => 0];
        }

        $data = json_decode($response, true);

        if (!is_array($data) || empty($data['instructors'])) {
            error_log('Unexpected API format or no programs.');
            return ['ok' => false, 'imported' => 0, 'updated' => 0];
        }

        $imported = 0;
        $updated  = 0;
        $menu_item = 'instructors';

        foreach ($data['instructors'] as $instructor) {
            // Find existing post by API program ID
            $existing = get_posts([
                'post_type'      => 'instructors',
                'meta_key'       => 'api_instructor_id',
                'meta_value'     => $instructor['instructor']['id'],
                'posts_per_page' => 1,
                'post_status'    => 'any',
                'fields'         => 'ids',
            ]);

            $postarr = [
                'post_type'    => 'instructors',
                'post_status'  => 'publish',
                'post_title'   => $instructor['instructor']['name'] ?? 'Untitled Program',
                'post_excerpt' => $instructor['instructor']['biography'] ?? '',
                // 🚫 Do NOT set post_content (we only store in ACF body_content)
            ];

            if (!empty($existing)) {
                $postarr['ID'] = $existing[0];
                $post_id = wp_update_post($postarr, true);
                if (!is_wp_error($post_id)) $updated++;
            } else {
                $post_id = wp_insert_post($postarr, true);
                if (!is_wp_error($post_id)) $imported++;
            }

            if (is_wp_error($post_id)) {
                error_log('Post error: ' . $post_id->get_error_message());
                continue;
            }

            if (!is_wp_error($post_id)) {
                // Featured Image
                if (!empty($instructor['instructor']['instructorimgPath'])) {
                    $imgFullPath = $imageSiteUrl . $instructor['instructor']['instructorimgPath'];
                    $image_id = my_import_image_to_media($imgFullPath, $post_id);
                    set_post_thumbnail($post_id, $image_id);
                }
            }

            // Process and replace images in body_content before saving
            $body_content = my_import_and_replace_images($instructor['instructor']['biography'] ?? '', $post_id);

            error_log('Instructor Processing: ' . $instructor['instructor']['name'] . ': ' . substr($body_content, 0, 100));

            // Save ACF fields
            if (function_exists('update_field')) {
                update_field('api_instructor_id', $instructor['instructor']['id'], $post_id);
                update_field('name',           $instructor['instructor']['name'] ?? '',        $post_id);
                update_field('biography',      $body_content, $post_id);
                update_field('excerpt',        $instructor['instructor']['biography'] ?? '',     $post_id);
                update_field('rank',           $instructor['instructor']['rank'] ?? '',        $post_id);
                update_field('active',         !empty($instructor['instructor']['active']),    $post_id);
            } else {
                update_post_meta($post_id, 'api_instructor_id', $instructor['instructor']['id']);
                update_post_meta($post_id, 'name',           $instructor['instructor']['name'] ?? '');
                update_post_meta($post_id, 'biography',   $body_content);
                update_post_meta($post_id, 'excerpt',        $instructor['instructor']['biography'] ?? '');
                update_post_meta($post_id, 'rank',           $instructor['instructor']['rank'] ?? '');
                update_post_meta($post_id, 'active',         !empty($instructor['instructor']['active']) ? 1 : 0);
            }
            error_log('Instructor Completed: ' . $instructor['instructor']['name'] . ': ' . substr($body_content, 0, 100));
        }
        

        return ['ok' => true, 'imported' => $imported, 'updated' => $updated, 'menu_item' => $menu_item];
    }

    /**
     * Download external images into Media Library and update HTML
     */
    function my_import_and_replace_images($html, $post_id)
    {
        if (empty($html)) return $html;

        // Ensure WordPress media functions are available
        if (!function_exists('download_url')) {
            require_once ABSPATH . 'wp-admin/includes/file.php';
        }
        if (!function_exists('media_handle_sideload')) {
            require_once ABSPATH . 'wp-admin/includes/media.php';
        }
        if (!function_exists('wp_generate_attachment_metadata')) {
            require_once ABSPATH . 'wp-admin/includes/image.php';
        }

        libxml_use_internal_errors(true);
        $doc = new DOMDocument();
        $doc->loadHTML(
            mb_encode_numericentity($html, [0x80, 0xffff, 0, 0xffff], 'UTF-8')
        );
        $images = $doc->getElementsByTagName('img');

        foreach ($images as $img) {
            $src = $img->getAttribute('src');

            // Skip if already WP media
            if (strpos($src, content_url()) !== false) {
                continue;
            }

            // Try downloading
            $tmp = download_url($src);
            if (is_wp_error($tmp)) {
                continue;
            }

            $file = [
                'name'     => basename(parse_url($src, PHP_URL_PATH)),
                'tmp_name' => $tmp,
            ];

            $id = media_handle_sideload($file, $post_id);
            if (!is_wp_error($id)) {
                $new_src = wp_get_attachment_url($id);
                $img->setAttribute('src', $new_src);
            }
        }

        return $doc->saveHTML();
    }

    /**
     * Import external image into Media Library and return attachment ID
     */
    function my_import_image_to_media($image_url, $post_id)
    {
        if (empty($image_url)) return false;

        // Skip if already in Media Library
        if (strpos($image_url, content_url()) !== false) return false;

        // Load WP media functions
        if (!function_exists('download_url')) {
            require_once ABSPATH . 'wp-admin/includes/file.php';
        }
        if (!function_exists('media_handle_sideload')) {
            require_once ABSPATH . 'wp-admin/includes/media.php';
        }
        if (!function_exists('wp_generate_attachment_metadata')) {
            require_once ABSPATH . 'wp-admin/includes/image.php';
        }

        // Download the image temporarily
        $tmp = download_url($image_url);
        if (is_wp_error($tmp)) return false;

        $file_array = [
            'name'     => basename(parse_url($image_url, PHP_URL_PATH)),
            'tmp_name' => $tmp,
        ];

        // Upload to Media Library
        $id = media_handle_sideload($file_array, $post_id);

        // Cleanup temp file on error
        if (is_wp_error($id)) {
            @unlink($tmp);
            return false;
        }

        // Suppress exif warnings while generating metadata
        $old_error_reporting = error_reporting();
        error_reporting($old_error_reporting & ~E_WARNING);

        $metadata = wp_generate_attachment_metadata($id, get_attached_file($id));
        wp_update_attachment_metadata($id, $metadata);

        error_reporting($old_error_reporting); // restore original

        return $id;
    }

    // Helper: normalize any "menu item" (string slug/url or array) into ['url' => ..., 'label' => ...]
if (!function_exists('dtp_normalize_menu_items')) {
    function dtp_normalize_menu_items($raw_items) {
        if (empty($raw_items)) return [];

        // If it's a single item (string or assoc array), wrap into array
        if (!is_array($raw_items) || (is_array($raw_items) && isset($raw_items['url']))) {
            $raw_items = [$raw_items];
        }

        $out = [];
        foreach ($raw_items as $it) {
            // Already structured
            if (is_array($it) && (isset($it['url']) || isset($it['label']))) {
                $out[] = $it;
                continue;
            }

            if (is_string($it)) {
                $slug_or_url = trim($it);

                // If it's a full URL, derive a decent label
                if (preg_match('#^https?://#i', $slug_or_url)) {
                    $path  = parse_url($slug_or_url, PHP_URL_PATH);
                    $base  = $path ? basename(untrailingslashit($path)) : '';
                    $label = $base ? ucwords(str_replace(['-', '_'], ' ', $base)) : 'Link';
                    $out[] = ['url' => $slug_or_url, 'label' => $label];
                    continue;
                }

                // Treat as slug: prefer an existing page by path
                $slug = sanitize_title($slug_or_url);
                $page = get_page_by_path($slug); // matches pages (and many CPT items)

                if ($page) {
                    $url   = get_permalink($page);
                    $label = get_the_title($page);
                } else {
                    // If this is a post type archive (e.g., 'programs' CPT)
                    if (post_type_exists($slug) && is_post_type_viewable($slug)) {
                        $url   = get_post_type_archive_link($slug);
                        $label = ucwords(str_replace(['-', '_'], ' ', $slug));
                    } else {
                        // Fallback to site/slug
                        $url   = home_url('/' . $slug . '/');
                        $label = ucwords(str_replace(['-', '_'], ' ', $slug));
                    }
                }

                $out[] = ['url' => $url, 'label' => $label];
            }
        }
        return $out;
    }
}