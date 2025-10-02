#!/bin/bash

# =========================================================
# CONFIG (interactive prompts with defaults)
# - Set SKIP_PROMPTS=1 to use env vars / defaults silently (CI-friendly)
# - Any value already present in the environment is respected
# =========================================================

prompt_var () {
  # usage: prompt_var VAR "Prompt text" "default" [secret]
  local __var_name="$1"
  local __prompt="$2"
  local __default="$3"
  local __secret="${4:-0}"
  local __current_val="${!__var_name}"
  local __input=""

  # If SKIP_PROMPTS=1 or value already provided via env, keep it
  if [ "${SKIP_PROMPTS:-0}" = "1" ] || [ -n "$__current_val" ]; then
    # If empty AND we have a default, set default
    if [ -z "$__current_val" ] && [ -n "$__default" ]; then
      eval "$__var_name=\"\$__default\""
    fi
    return
  fi

  if [ "$__secret" = "1" ]; then
    read -r -s -p "$__prompt [$__default]: " __input
    echo
  else
    read -r -p "$__prompt [$__default]: " __input
  fi
  if [ -z "$__input" ]; then
    __input="$__default"
  fi
  eval "$__var_name=\"\$__input\""
}

echo "🔧 Interactive setup — press Enter to accept defaults."

# --- Capture original working dir + script dir BEFORE any cd ---
ORIGINAL_CWD="$(pwd)"

# Works if run with bash or sh; handles symlinks too
__src="${BASH_SOURCE[0]:-$0}"
while [ -h "$__src" ]; do
  __dir="$(cd -P "$(dirname "$__src")" && pwd)"
  __src="$(readlink "$__src")"
  case "$__src" in
    /*) ;; # absolute
    *) __src="$__dir/$__src" ;;
  esac
done
ORIGINAL_SCRIPT_DIR="$(cd -P "$(dirname "$__src")" && pwd)"
export ORIGINAL_SCRIPT_DIR ORIGINAL_CWD


# ---------- DB ----------
prompt_var DB_NAME              "Database name"                    "wp_db_cli"
prompt_var DB_USER              "Database user"                    "root"
prompt_var DB_PASS              "Database password"                "admin123" 1
prompt_var DB_HOST              "Database host"                    "localhost"

prompt_var MYSQL_ROOT_USER      "MySQL root user"                  "root"
prompt_var MYSQL_ROOT_PASS      "MySQL root password"              "admin123" 1

# ---------- WordPress ----------
prompt_var WP_URL               "Site URL"                         "http://wp_cli.local"
prompt_var WP_TITLE             "Site title"                       "My WordPress Site"
prompt_var WP_ADMIN_USER        "WP admin username"                "admin"
prompt_var WP_ADMIN_PASS        "WP admin password"                "Admin123$" 1
prompt_var WP_ADMIN_EMAIL       "WP admin email"                   "admin@example.com"

# ---------- Paths ----------
prompt_var WP_PATH              "WordPress install path"           "/var/www/html/wordpress-cli"
prompt_var STATIC_SITE_PATH     "Static site path (leave blank to skip)"   ""
prompt_var MENU_NAME            "Primary menu name"                "Main Menu"

# Derived (don’t prompt)
STATIC_IMAGES_PATH="$STATIC_SITE_PATH/images"
STATIC_CSS_PATH="$STATIC_SITE_PATH/css"

echo
echo "📋 Config summary:"
echo "  DB_NAME=$DB_NAME"
echo "  DB_USER=$DB_USER"
echo "  DB_HOST=$DB_HOST"
echo "  MYSQL_ROOT_USER=$MYSQL_ROOT_USER"
echo "  WP_URL=$WP_URL"
echo "  WP_TITLE=$WP_TITLE"
echo "  WP_ADMIN_USER=$WP_ADMIN_USER"
echo "  WP_ADMIN_EMAIL=$WP_ADMIN_EMAIL"
echo "  WP_PATH=$WP_PATH"
echo "  STATIC_SITE_PATH=${STATIC_SITE_PATH:-<empty>}"
echo "  STATIC_IMAGES_PATH=$STATIC_IMAGES_PATH"
echo "  STATIC_CSS_PATH=$STATIC_CSS_PATH"
echo "  MENU_NAME=$MENU_NAME"
echo

# ========== INSTALL SCRIPT ==========

echo "🚀 Starting WordPress Installation..."

# Create installation directory
mkdir -p "$WP_PATH"
cd "$WP_PATH" || exit 1

# ---------- Host & Apache VirtualHost (non-destructive) ----------
CREATE_VIRTUAL_HOST="${CREATE_VIRTUAL_HOST:-0}"

if [ "$CREATE_VIRTUAL_HOST" = "1" ]; then
  echo "🌐 Preparing local host + Apache vhost..."

  # Derive host from WP_URL
  WP_HOST="$(echo "$WP_URL" | sed -E 's~^[a-z]+://~~; s~/.*$~~; s~:.*$~~')"
  [ -z "$WP_HOST" ] && { echo "❌ Could not derive host from WP_URL=$WP_URL"; exit 1; }
  echo "🔎 Derived host: $WP_HOST"

  # sudo helper
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

  # 1) /etc/hosts (append if missing, with newline safety + dedupe)
  HOSTS_FILE="/etc/hosts"
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

  # Only append if hostname not already mapped on 127.0.0.1
  if ! grep -Eq "^[[:space:]]*127\.0\.0\.1[[:space:]].*\b${WP_HOST}\b" "$HOSTS_FILE"; then
    echo "🧾 Adding hosts entry → 127.0.0.1 ${WP_HOST}"

    # Ensure file ends with a newline, otherwise appending will glue to last line
    if [ -n "$($SUDO tail -c1 "$HOSTS_FILE" 2>/dev/null)" ]; then
      $SUDO sh -c "printf '\n' >> '$HOSTS_FILE'"
    fi

    # Remove any existing non-comment lines containing the host (dedupe/clean)
    TMP_H="$(mktemp)"
    $SUDO awk -v host="$WP_HOST" '
      /^[[:space:]]*#/ { print; next }               # keep comments
      {
        drop=0
        for (i=1;i<=NF;i++) if ($i==host) { drop=1; break }
        if (!drop) print
      }' "$HOSTS_FILE" > "$TMP_H"
    $SUDO cp "$TMP_H" "$HOSTS_FILE"
    rm -f "$TMP_H"

    # Append the correct mapping (with its own newline)
    $SUDO sh -c "printf '127.0.0.1\t%s\n' '$WP_HOST' >> '$HOSTS_FILE'"
  else
    echo "ℹ️ Hosts entry for ${WP_HOST} already present."
  fi

  # 2) Apache block inside 000-default.conf (append or update only our marked block)
  if command -v apache2 >/dev/null 2>&1 || ps -A | grep -q apache2; then
    VHOST_FILE="/etc/apache2/sites-available/000-default.conf"
    [ -f "$VHOST_FILE" ] || { echo "❌ $VHOST_FILE not found"; exit 1; }

    TS="$(date +%Y%m%d-%H%M%S)"
    $SUDO cp "$VHOST_FILE" "${VHOST_FILE}.bak.${TS}"
    echo "🗄️  Backup created: ${VHOST_FILE}.bak.${TS}"

    LOG_STEM="$(basename "$WP_PATH" | tr -cd '[:alnum:]_-')"
    [ -z "$LOG_STEM" ] && LOG_STEM="wordpress"

    BLOCK_BEGIN="# BEGIN wp-cli ${WP_HOST}"
    BLOCK_END="# END wp-cli ${WP_HOST}"

    # Build fresh block content
    TMP_BLOCK="$(mktemp)"
    cat > "$TMP_BLOCK" <<EOF
${BLOCK_BEGIN}
<VirtualHost *:80>
    ServerName ${WP_HOST}
    ServerAlias ${WP_HOST}
    DocumentRoot ${WP_PATH}

    ErrorLog \${APACHE_LOG_DIR}/${LOG_STEM}.error.log
    CustomLog \${APACHE_LOG_DIR}/${LOG_STEM}.access.log combined

    <Directory ${WP_PATH}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
${BLOCK_END}
EOF

    # If our block exists → replace it; else → append it
    if grep -qF "$BLOCK_BEGIN" "$VHOST_FILE"; then
      echo "✏️ Updating existing vhost block for ${WP_HOST} in 000-default.conf"
      TMP_FILE="$(mktemp)"
      awk -v start="$BLOCK_BEGIN" -v end="$BLOCK_END" '
        BEGIN {inblk=0}
        {
          if ($0==start) {print start; inblk=1; next}
          if ($0==end)   {print end; inblk=0; next}
          if (!inblk) print
        }' "$VHOST_FILE" > "$TMP_FILE"
      # Insert fresh block at the end (keeps order, avoids nested awk complexity)
      $SUDO bash -c "cat '$TMP_FILE' > '$VHOST_FILE'"
      $SUDO bash -c "printf '\n\n' >> '$VHOST_FILE'"
      $SUDO bash -c "cat '$TMP_BLOCK' >> '$VHOST_FILE'"
      rm -f "$TMP_FILE"
    else
      echo "➕ Appending new vhost block for ${WP_HOST} to 000-default.conf"
      $SUDO bash -c "printf '\n\n' >> '$VHOST_FILE'"
      $SUDO bash -c "cat '$TMP_BLOCK' >> '$VHOST_FILE'"
    fi
    rm -f "$TMP_BLOCK"

    # Ensure mod_rewrite, test & reload (no site renames/enables here)
    $SUDO a2enmod rewrite >/dev/null 2>&1 || true
    echo "🧪 apache2ctl configtest..."
    if $SUDO apache2ctl configtest; then
      echo "🔄 Reloading Apache..."
      $SUDO systemctl reload apache2 || $SUDO service apache2 reload
      echo "✅ Apache reloaded with ${WP_HOST} → ${WP_PATH} (inside 000-default.conf)"
    else
      echo "❌ Apache config test failed — restoring backup."
      $SUDO cp "${VHOST_FILE}.bak.${TS}" "$VHOST_FILE"
      exit 1
    fi
  else
    echo "⚠️ Apache not detected — skipping VirtualHost update."
  fi
else
  echo "⏭️ CREATE_VIRTUAL_HOST!=1 — skipping hosts + 000-default.conf work."
fi

# ---------- Database Setup ----------
echo "🛢️ Creating database (if not exists)..."
mysql -u"$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASS" -e \
  "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# ---------- Download WordPress ----------
echo "⬇️ Downloading WordPress..."
wp core download --path="$WP_PATH" --allow-root

# ---------- Config ----------
echo "⚙️ Creating wp-config.php..."
wp config create \
  --dbname="$DB_NAME" \
  --dbuser="$DB_USER" \
  --dbpass="$DB_PASS" \
  --dbhost="$DB_HOST" \
  --path="$WP_PATH" \
  --skip-check --allow-root

# ---- Raise PHP execution time in wp-config.php (idempotent) ----
WPCFG="$WP_PATH/wp-config.php"

if [ -f "$WPCFG" ]; then
  # Skip if we already added it
  if ! grep -q "max_execution_time.*3600" "$WPCFG"; then
    echo "⏱️ Adding max_execution_time=3600 to wp-config.php …"
    SNIPPET="$(mktemp)"
    cat > "$SNIPPET" <<'PHP'
/* Bump PHP execution time for heavy tasks */
@ini_set('max_execution_time', '3600');  // 3600 seconds = 1 hour
@set_time_limit(3600);
PHP

    TMP="$(mktemp)"
    awk -v f="$SNIPPET" '
      BEGIN{done=0}
      { print }
      !done && /That'"'"'s all, stop editing! Happy publishing\./ {
        system("cat " f); 
        done=1
      }
    ' "$WPCFG" > "$TMP" && mv "$TMP" "$WPCFG"
    rm -f "$SNIPPET"
    echo "✅ Inserted execution time snippet after the stop-editing marker."
  else
    echo "ℹ️ max_execution_time snippet already present; skipping."
  fi
else
  echo "❌ wp-config.php not found at $WPCFG (did wp config create run?)"
fi

# ---------- Install WP ----------
echo "📝 Installing WordPress..."
wp core install \
  --url="$WP_URL" \
  --title="$WP_TITLE" \
  --admin_user="$WP_ADMIN_USER" \
  --admin_password="$WP_ADMIN_PASS" \
  --admin_email="$WP_ADMIN_EMAIL" \
  --path="$WP_PATH" --allow-root

# ---------- Install local plugins (folder or zip) ----------
echo "📦 Installing local plugins from script/launch directory (dir or zip)..."

# 1) List of local plugins. Put either a folder name or a zip filename.
LOCAL_PLUGINS=(
  "devteampro-dotnet-wp"   # folder beside the script
  # "another-plugin"       # folder
  # "some-plugin.zip"      # zip
  # "/absolute/path/custom-plugin" or "/abs/path/custom-plugin.zip"
)

# If you leave the array empty, we can auto-discover; otherwise we use your list.
if [ "${#LOCAL_PLUGINS[@]}" -eq 0 ]; then
  echo "🔎 Auto-discovering local plugins (*.zip and directories) ..."
  mapfile -t LOCAL_PLUGINS < <(
    { [ -n "$ORIGINAL_SCRIPT_DIR" ] && find "$ORIGINAL_SCRIPT_DIR" -maxdepth 1 -mindepth 1 \( -type d -o -type f -name '*.zip' \) -printf "%p\n"; } 2>/dev/null
    { [ -n "$ORIGINAL_CWD" ]        && find "$ORIGINAL_CWD"        -maxdepth 1 -mindepth 1 \( -type d -o -type f -name '*.zip' \) -printf "%p\n"; } 2>/dev/null
  )
  # De-dupe
  if [ "${#LOCAL_PLUGINS[@]}" -gt 0 ]; then
    LOCAL_PLUGINS=($(printf "%s\n" "${LOCAL_PLUGINS[@]}" | awk '!seen[$0]++'))
  fi
fi

# Helper: resolve an item to a full path (dir or zip)
resolve_item_path() {
  local item="$1"
  # absolute or relative existing path?
  if [ -e "$item" ]; then echo "$item"; return 0; fi
  # try script dir / launch dir
  for base in "$ORIGINAL_SCRIPT_DIR" "$ORIGINAL_CWD"; do
    if [ -e "$base/$item" ]; then echo "$base/$item"; return 0; fi
  done
  return 1
}

PLUGINS_DIR="$WP_PATH/wp-content/plugins"
[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"
$SUDO mkdir -p "$PLUGINS_DIR"

# multisite flag
IS_MS="$(wp eval 'echo is_multisite()?1:0;' --path="$WP_PATH" --allow-root 2>/dev/null || echo 0)"
ACTIVATE_FLAG=$([ "$IS_MS" = "1" ] && echo "--activate-network" || echo "--activate")

for item in "${LOCAL_PLUGINS[@]}"; do
  ITEM_PATH="$(resolve_item_path "$item")" || { echo "❌ Not found: $item"; continue; }

  if [ -d "$ITEM_PATH" ]; then
    # ===== Directory plugin install =====
    SLUG="$(basename "$ITEM_PATH")"
    DEST_DIR="$PLUGINS_DIR/$SLUG"
    echo "📁 Installing directory plugin: $SLUG"
    if command -v rsync >/dev/null 2>&1; then
      $SUDO rsync -a --delete "$ITEM_PATH"/ "$DEST_DIR"/
    else
      # Fallback without rsync (less ideal if removing files)
      $SUDO rm -rf "$DEST_DIR"
      $SUDO mkdir -p "$DEST_DIR"
      $SUDO cp -a "$ITEM_PATH"/. "$DEST_DIR"/
    fi
    # basic perms (you also run a full perms pass later)
    $SUDO find "$DEST_DIR" -type d -exec chmod 755 {} \;
    $SUDO find "$DEST_DIR" -type f -exec chmod 644 {} \;

    # Try to activate
    if wp plugin activate "$SLUG" --path="$WP_PATH" --allow-root >/dev/null 2>&1; then
      echo "✅ Activated (dir): $SLUG"
    else
      # WP-CLI sometimes warns yet activates; double-check:
      if wp plugin is-active "$SLUG" --path="$WP_PATH" --allow-root; then
        echo "✅ Activated (dir, with warnings): $SLUG"
      else
        echo "⚠️ Could not activate (dir): $SLUG"
      fi
    fi

  elif [ -f "$ITEM_PATH" ] && [[ "$ITEM_PATH" == *.zip ]]; then
    # ===== ZIP plugin install =====
    ZIP_BASENAME="$(basename "$ITEM_PATH")"
    DEST_ZIP_PATH="$PLUGINS_DIR/$ZIP_BASENAME"
    echo "🧩 Installing zip plugin: $ZIP_BASENAME"
    $SUDO cp -f "$ITEM_PATH" "$DEST_ZIP_PATH"
    $SUDO chmod 644 "$DEST_ZIP_PATH"

    if wp plugin install "$DEST_ZIP_PATH" $ACTIVATE_FLAG --force --path="$WP_PATH" --allow-root; then
      echo "✅ Installed & activated (zip): $ZIP_BASENAME"
    else
      echo "⚠️ Install reported an issue for zip: $ZIP_BASENAME"
    fi
  else
    echo "⚠️ Unsupported item (not dir or .zip): $ITEM_PATH"
  fi
done

# ---------- Theme Setup ----------
echo "🎨 Installing Hello Elementor Theme..."
wp theme install hello-elementor --activate --allow-root

# Remove all inactive themes
echo "🧹 Removing inactive themes..."
wp theme delete $(wp theme list --status=inactive --field=name --allow-root) --allow-root || true

# ---------- Post-install Tweaks ----------
echo "🔧 Setting defaults..."
wp option update blogdescription "Just another WordPress site" --allow-root
wp plugin update --all --allow-root

# ---------- Install Essential Plugins ----------
ESSENTIAL_PLUGINS=(
  "advanced-custom-fields"
  # "elementor"
  # "elementor-pro"
)
echo "🔌 Installing essential plugins: ${ESSENTIAL_PLUGINS[*]} ..."
for plugin in "${ESSENTIAL_PLUGINS[@]}"; do
  if ! wp plugin is-installed "$plugin" --allow-root; then
    wp plugin install "$plugin" --activate --allow-root
  else
    wp plugin activate "$plugin" --allow-root
  fi
done

# ---------- Register CPT + ACF fields via mu-plugin ----------
echo "🧩 Adding mu-plugin for CPT 'programs' + ACF fields..."

MU_DIR="$WP_PATH/wp-content/mu-plugins"
MU_FILE="$MU_DIR/register-programs-cpt-and-acf.php"
mkdir -p "$MU_DIR"

cat > "$MU_FILE" <<'PHP'
<?php
/**
 * Plugin Name: Programs CPT + ACF (mu-plugin)
 * Description: Registers "programs" CPT and ACF field groups via code.
 * Author: WP CLI Script
 * Version: 1.0.0
 */

add_action('init', function () {
    // Register CPT: programs
    $labels = [
        'name'               => 'Programs',
        'singular_name'      => 'Program',
        'menu_name'          => 'Programs',
        'name_admin_bar'     => 'Program',
        'add_new'            => 'Add New',
        'add_new_item'       => 'Add New Program',
        'new_item'           => 'New Program',
        'edit_item'          => 'Edit Program',
        'view_item'          => 'View Program',
        'all_items'          => 'All Programs',
        'search_items'       => 'Search Programs',
        'parent_item_colon'  => 'Parent Programs:',
        'not_found'          => 'No programs found.',
        'not_found_in_trash' => 'No programs found in Trash.'
    ];

    $args = [
        'labels'             => $labels,
        'public'             => true,
        'has_archive'        => true,
        'rewrite'            => ['slug' => 'programs', 'with_front' => false],
        'menu_icon'          => 'dashicons-welcome-learn-more',
        'show_in_rest'       => true, // Gutenberg/REST
        'supports'           => ['title','editor','thumbnail','excerpt','revisions'],
        'taxonomies'         => [],
    ];

    register_post_type('programs', $args);
}, 0);

/**
 * ACF field groups (loaded in PHP; no UI export needed).
 * Requires ACF to be active.
 */
add_action('acf/init', function () {
    if (!function_exists('acf_add_local_field_group')) {
        return;
    }

    // Field Group: Program Details
    acf_add_local_field_group([
        'key' => 'group_programs_details',
        'title' => 'Program Details',
        'fields' => [
            [
                'key' => 'field_programs_rank',
                'label' => 'Rank',
                'name' => 'rank',
                'type' => 'number',
                'instructions' => 'Used to order Programs (lower number = higher rank).',
                'required' => 0,
                'min' => 0,
                'step' => 1,
            ],
            [
                'key' => 'field_programs_banner',
                'label' => 'Program Banner',
                'name' => 'program_banner',
                'type' => 'image',
                'return_format' => 'array', // matches your template usage
                'preview_size' => 'medium',
                'library' => 'all',
            ],
            [
                'key' => 'field_programs_modules',
                'label' => 'Modules',
                'name' => 'modules',
                'type' => 'repeater',
                'button_label' => 'Add Module',
                'layout' => 'row',
                'sub_fields' => [
                    [
                        'key' => 'field_programs_module_title',
                        'label' => 'Title',
                        'name' => 'title',
                        'type' => 'text',
                    ],
                    [
                        'key' => 'field_programs_module_description',
                        'label' => 'Description',
                        'name' => 'description',
                        'type' => 'textarea',
                        'rows' => 3,
                    ],
                ],
            ],
            [
                'key' => 'field_programs_first_name',
                'label' => 'First Name',
                'name' => 'first_name',
                'type' => 'text',
            ],
            [
                'key' => 'field_programs_body_content',
                'label' => 'Body Content',
                'name' => 'body_content',
                'type' => 'wysiwyg',
                'tabs' => 'all',
                'toolbar' => 'full',
                'media_upload' => 1,
            ],
        ],
        'location' => [
            [
                [
                    'param' => 'post_type',
                    'operator' => '==',
                    'value' => 'programs',
                ],
            ],
        ],
        'position' => 'normal',
        'style' => 'default',
        'label_placement' => 'top',
        'instruction_placement' => 'label',
        'active' => true,
        'show_in_rest' => 0,
    ]);
});
PHP

# Make sure mu-plugin is readable
chmod 644 "$MU_FILE"

# Flush permalinks so /programs archive works immediately
wp rewrite flush --hard --path="$WP_PATH" --allow-root

echo "✅ CPT 'programs' + ACF fields installed (mu-plugin)."


# ---------- Register CPT "instructors" + ACF fields via mu-plugin ----------
echo "🧩 Adding mu-plugin for CPT 'instructors' + ACF fields..."

MU_DIR="$WP_PATH/wp-content/mu-plugins"
MU_FILE_INSTRUCTORS="$MU_DIR/register-instructors-cpt-and-acf.php"
mkdir -p "$MU_DIR"

cat > "$MU_FILE_INSTRUCTORS" <<'PHP'
<?php
/**
 * Plugin Name: Instructors CPT + ACF (mu-plugin)
 * Description: Registers "instructors" custom post type and ACF field group via code.
 * Author: WP CLI Script
 * Version: 1.0.0
 */

add_action('init', function () {
    $labels = [
        'name'               => 'Instructors',
        'singular_name'      => 'Instructor',
        'menu_name'          => 'Instructors',
        'name_admin_bar'     => 'Instructor',
        'add_new'            => 'Add New',
        'add_new_item'       => 'Add New Instructor',
        'new_item'           => 'New Instructor',
        'edit_item'          => 'Edit Instructor',
        'view_item'          => 'View Instructor',
        'all_items'          => 'All Instructors',
        'search_items'       => 'Search Instructors',
        'not_found'          => 'No instructors found.',
        'not_found_in_trash' => 'No instructors found in Trash.'
    ];

    $args = [
        'labels'             => $labels,
        'public'             => true,
        'has_archive'        => true,
        'rewrite'            => ['slug' => 'instructors', 'with_front' => false],
        'menu_icon'          => 'dashicons-groups',
        'show_in_rest'       => true,
        'supports'           => ['title','editor','thumbnail','excerpt','revisions'],
        'taxonomies'         => [], // add if needed
    ];

    register_post_type('instructors', $args);
}, 0);

/**
 * ACF local fields for "instructors"
 * Matches your archive sorting (by "rank") and optional "first_name" use.
 */
add_action('acf/init', function () {
    if (!function_exists('acf_add_local_field_group')) {
        return;
    }

    acf_add_local_field_group([
        'key' => 'group_instructors_details',
        'title' => 'Instructor Details',
        'fields' => [
            [
                'key' => 'field_instructor_rank',
                'label' => 'Rank',
                'name' => 'rank',
                'type' => 'number',
                'instructions' => 'Used to order Instructors (lower number appears first).',
                'min' => 0,
                'step' => 1,
            ],
            [
                'key'   => 'field_instructor_first_name',
                'label' => 'First Name',
                'name'  => 'first_name',
                'type'  => 'text',
            ],
            [
                'key'   => 'field_instructor_last_name',
                'label' => 'Last Name',
                'name'  => 'last_name',
                'type'  => 'text',
            ],
            [
                'key'           => 'field_instructor_headshot',
                'label'         => 'Headshot',
                'name'          => 'headshot',
                'type'          => 'image',
                'return_format' => 'array',
                'preview_size'  => 'medium',
                'library'       => 'all',
            ],
            [
                'key'   => 'field_instructor_bio',
                'label' => 'Biography',
                'name'  => 'biography',
                'type'  => 'wysiwyg',
                'tabs'  => 'all',
                'toolbar' => 'full',
                'media_upload' => 1,
            ],
            [
                'key'   => 'field_instructor_expertise',
                'label' => 'Areas of Expertise',
                'name'  => 'expertise',
                'type'  => 'repeater',
                'button_label' => 'Add Expertise',
                'layout' => 'row',
                'sub_fields' => [
                    [
                        'key'   => 'field_instructor_expertise_item',
                        'label' => 'Expertise',
                        'name'  => 'item',
                        'type'  => 'text',
                    ],
                ],
            ],
            [
                'key'   => 'field_instructor_social',
                'label' => 'Social Links',
                'name'  => 'social_links',
                'type'  => 'repeater',
                'button_label' => 'Add Social Link',
                'layout' => 'table',
                'sub_fields' => [
                    [
                        'key'   => 'field_instructor_social_label',
                        'label' => 'Label',
                        'name'  => 'label',
                        'type'  => 'text',
                    ],
                    [
                        'key'   => 'field_instructor_social_url',
                        'label' => 'URL',
                        'name'  => 'url',
                        'type'  => 'url',
                    ],
                ],
            ],
            [
                'key'   => 'field_instructor_email',
                'label' => 'Email',
                'name'  => 'email',
                'type'  => 'email',
            ],
            [
                'key'   => 'field_instructor_phone',
                'label' => 'Phone',
                'name'  => 'phone',
                'type'  => 'text',
            ],
        ],
        'location' => [
            [
                [
                    'param'    => 'post_type',
                    'operator' => '==',
                    'value'    => 'instructors',
                ],
            ],
        ],
        'position' => 'normal',
        'style' => 'default',
        'label_placement' => 'top',
        'instruction_placement' => 'label',
        'active' => true,
        'show_in_rest' => 0,
    ]);
});
PHP

chmod 644 "$MU_FILE_INSTRUCTORS"

# Flush permalinks so /instructors archive works right away
wp rewrite flush --hard --path="$WP_PATH" --allow-root

echo "✅ CPT 'instructors' + ACF fields installed (mu-plugin)."


# ---------- Cleanup Plugins ----------
echo "🧹 Removing inactive plugins..."
INACTIVE_PLUGINS=$(wp plugin list --status=inactive --field=name --allow-root)
if [ -n "$INACTIVE_PLUGINS" ]; then
  wp plugin delete $INACTIVE_PLUGINS --allow-root
else
  echo "✅ No inactive plugins found."
fi

# ---------- Permalink Setup ----------
echo "🔗 Setting permalink structure..."
if command -v apache2 >/dev/null 2>&1 || ps -A | grep -q apache2; then
  echo "⚡ Apache detected → setting permalinks and regenerating .htaccess"
  wp rewrite structure '/%postname%/' --hard --allow-root

  if [ ! -f "$WP_PATH/.htaccess" ]; then
    cat > "$WP_PATH/.htaccess" <<'EOL'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOL
    echo "✅ Default .htaccess created"
  fi
elif command -v nginx >/dev/null 2>&1 || ps -A | grep -q nginx; then
  echo "🌐 Nginx detected → only setting permalink option in DB"
  wp rewrite structure '/%postname%/' --allow-root
  echo "⚠️ Remember to configure Nginx manually for pretty permalinks."
else
  echo "❓ Could not detect Apache or Nginx → skipping rewrite rules."
fi

# ---------- Create Primary Menu (optional but harmless) ----------
if ! wp menu list --allow-root | grep -q "$MENU_NAME"; then
  echo "🍽️ Creating menu: $MENU_NAME"
  wp menu create "$MENU_NAME" --allow-root
  # Best effort to assign first available location (jq recommended)
  if command -v jq >/dev/null 2>&1; then
    MENU_LOCATION=$(wp menu location list --allow-root --format=json | jq -r '.[0].location')
    if [ -n "$MENU_LOCATION" ] && [ "$MENU_LOCATION" != "null" ]; then
      wp menu location assign "$MENU_NAME" "$MENU_LOCATION" --allow-root
      echo "✅ Menu assigned to location: $MENU_LOCATION"
    else
      echo "⚠️ No menu location found. Menu created but not assigned."
    fi
  else
    echo "ℹ️ jq not found — skipping auto-assign of menu location."
  fi
fi

# ---------- Child Theme (always create/activate) ----------
echo "🎨 Ensuring Hello Elementor Child Theme exists..."
CHILD_THEME="hello-elementor-child"
CHILD_PATH="$WP_PATH/wp-content/themes/$CHILD_THEME"
STYLE_FILE="$CHILD_PATH/style.css"

if [ ! -d "$CHILD_PATH" ]; then
  wp scaffold child-theme "$CHILD_THEME" \
    --parent_theme=hello-elementor \
    --theme_name="Hello Elementor Child" \
    --author="WP CLI Script" \
    --activate --allow-root
else
  wp theme activate "$CHILD_THEME" --allow-root
fi

# Copy screenshot from parent (optional)
PARENT_THEME="hello-elementor"
PARENT_PATH="$WP_PATH/wp-content/themes/$PARENT_THEME"
SCREEN_FOUND=""
for ext in png jpg jpeg webp; do
  if [ -f "$PARENT_PATH/screenshot.$ext" ]; then
    cp "$PARENT_PATH/screenshot.$ext" "$CHILD_PATH/screenshot.$ext"
    SCREEN_FOUND="$CHILD_PATH/screenshot.$ext"
    for rmext in png jpg jpeg webp; do
      if [ "$rmext" != "$ext" ] && [ -f "$CHILD_PATH/screenshot.$rmext" ]; then
        rm -f "$CHILD_PATH/screenshot.$rmext"
      fi
    done
    echo "🖼️ Copied parent theme screenshot → $SCREEN_FOUND"
    break
  fi
done
[ -z "$SCREEN_FOUND" ] && echo "⚠️ No screenshot.(png|jpg|jpeg|webp) found in $PARENT_PATH (skipping)."

# ---------- Import Static Site (only if path provided & exists) ----------
STATIC_PRESENT=0
if [ -n "$STATIC_SITE_PATH" ] && [ -d "$STATIC_SITE_PATH" ]; then
  STATIC_PRESENT=1
else
  echo "⚠️ Skipping static site import — STATIC_SITE_PATH not set or directory missing."
fi

if [ "$STATIC_PRESENT" -eq 1 ]; then
  echo "📄 Importing static HTML pages and media from: $STATIC_SITE_PATH"

  # ---------- Media Import (root-relative URLs) ----------
  echo "🖼️ Importing images into Media Library..."
  declare -A MEDIA_MAP
  if [ -d "$STATIC_IMAGES_PATH" ]; then
    shopt -s nullglob
    for IMG in "$STATIC_IMAGES_PATH"/*.{jpg,jpeg,png,gif,webp,JPG,JPEG,PNG,GIF,WEBP}; do
      BASENAME=$(basename "$IMG")
      ATTACHMENT_ID=$(wp media import "$IMG" --porcelain --allow-root)
      REL_PATH=$(wp post meta get "$ATTACHMENT_ID" _wp_attached_file --allow-root)
      REL_URL="/wp-content/uploads/$REL_PATH"
      MEDIA_MAP["$BASENAME"]="$REL_URL"
      echo "📤 Imported $BASENAME → $REL_URL"
    done
    shopt -u nullglob
  else
    echo "⚠️ No images directory found at $STATIC_IMAGES_PATH"
  fi

  # ---------- Import HTML Pages ----------
  shopt -s nullglob
  for FILE in "$STATIC_SITE_PATH"/*.html; do
    [ -e "$FILE" ] || continue
    BASENAME_HTML=$(basename "$FILE" .html)
    TITLE=$(echo "$BASENAME_HTML" | sed 's/-/ /g; s/\b\(.\)/\u\1/g')
    CONTENT=$(cat "$FILE")

    # Replace local image paths with WP media URLs
    for IMG_NAME in "${!MEDIA_MAP[@]}"; do
      REL_URL="${MEDIA_MAP[$IMG_NAME]}"
      CONTENT=${CONTENT//images\/$IMG_NAME/$REL_URL}
      CONTENT=${CONTENT//.\/images\/$IMG_NAME/$REL_URL}
      CONTENT=${CONTENT//\/images\/$IMG_NAME/$REL_URL}
    done

    # Strip inline CSS / local <link> CSS (avoid duplication)
    CONTENT=$(echo "$CONTENT" | perl -0777 -pe 's/<style\b[^>]*>.*?<\/style>//gis')
    CONTENT=$(echo "$CONTENT" | perl -0777 -pe 's/<link\b[^>]*href=(?:"|\x27)(?!https?:\/\/)[^"\x27>]+\.css(?:"|\x27)[^>]*>//gis')
    CONTENT=$(echo "$CONTENT" | perl -0777 -pe 's/<link\b[^>]*href=(?!https?:\/\/)[^ >]+\.css[^>]*>//gis')

    echo "➡️ Importing $TITLE page..."
    PAGE_ID=$(wp post create --post_type=page --post_title="$TITLE" --post_content="$CONTENT" --post_status=publish --porcelain --allow-root)
    if [ -n "$PAGE_ID" ]; then
      wp menu item add-post "$MENU_NAME" "$PAGE_ID" --allow-root
    fi
    if [[ "$TITLE" == "Home" ]]; then
      wp option update show_on_front 'page' --allow-root
      wp option update page_on_front "$PAGE_ID" --allow-root
    fi
  done
  shopt -u nullglob

  # ---------- CSS Bundling into Child Theme ----------
  echo "🎨 Bundling CSS from static site into child theme..."
  BUNDLE_TMP="$(mktemp)"

  # 1) Collect CSS from standalone files
  if [ -d "$STATIC_CSS_PATH" ]; then
    echo "📦 Collecting CSS from $STATIC_CSS_PATH ..."
    find "$STATIC_CSS_PATH" -type f -name '*.css' -print0 | while IFS= read -r -d '' cssf; do
      echo -e "\n/* ===== File: ${cssf#$STATIC_SITE_PATH/} ===== */" >> "$BUNDLE_TMP"
      cat "$cssf" >> "$BUNDLE_TMP"
      echo >> "$BUNDLE_TMP"
    done
  fi

  # 2) Collect inline/linked local CSS from HTML sources
  echo "🧩 Extracting CSS from HTML files..."
  shopt -s nullglob
  for FILE in "$STATIC_SITE_PATH"/*.html; do
    [ -e "$FILE" ] || continue
    REL_HTML="${FILE#$STATIC_SITE_PATH/}"
    HTML_DIR="$(dirname "$FILE")"

    INLINE_CSS=$(perl -0777 -ne 'while (/<style[^>]*>(.*?)<\/style>/gis){print "$1\n"}' "$FILE")
    if [ -n "$INLINE_CSS" ]; then
      echo -e "\n/* ===== Inline <style> from: $REL_HTML ===== */" >> "$BUNDLE_TMP"
      echo "$INLINE_CSS" >> "$BUNDLE_TMP"
      echo >> "$BUNDLE_TMP"
    fi

    while IFS= read -r css_href; do
      css_href="${css_href%\"}"; css_href="${css_href#\"}"
      if [[ "$css_href" =~ ^https?:// ]]; then
        continue
      fi
      if [[ "$css_href" == /* ]]; then
        CANDIDATE="$STATIC_SITE_PATH${css_href}"
      else
        CANDIDATE="$(realpath -m "$HTML_DIR/$css_href")"
      fi
      if [ -f "$CANDIDATE" ]; then
        echo -e "\n/* ===== Linked CSS: ${css_href} (from $REL_HTML) ===== */" >> "$BUNDLE_TMP"
        cat "$CANDIDATE" >> "$BUNDLE_TMP"
        echo >> "$BUNDLE_TMP"
      fi
    done < <(grep -oiE 'href=("|\x27)[^"\x27]+\.css("|\x27)' "$FILE" | sed -E 's/^href=//I')
  done
  shopt -u nullglob

  # 3) Backup style.css
  if [ -f "$STYLE_FILE" ]; then
    TS="$(date +%Y%m%d-%H%M%S)"
    cp "$STYLE_FILE" "$STYLE_FILE.bak.$TS"
    echo "🗄️  Backed up existing style.css → style.css.bak.$TS"
  fi

  # 4) Ensure header exists; append bundle
  if [ ! -f "$STYLE_FILE" ]; then
    cat > "$STYLE_FILE" <<'CSSHDR'
/*
Theme Name: Hello Elementor Child
Template: hello-elementor
Description: Child theme – auto-bundled CSS
*/
CSSHDR
  fi

  echo -e "\n/* === Auto-bundled CSS BEGIN: $(date -u +"%Y-%m-%d %H:%M:%S UTC") === */" >> "$STYLE_FILE"
  cat "$BUNDLE_TMP" >> "$STYLE_FILE"
  echo -e "/* === Auto-bundled CSS END === */\n" >> "$STYLE_FILE"
  rm -f "$BUNDLE_TMP"

  # 5) Remove earlier per-file enqueue helper (if any)
  FUNCTIONS_FILE="$CHILD_PATH/functions.php"
  if [ -f "$FUNCTIONS_FILE" ]; then
    sed -i '/# Enqueue custom CSS from static site/,/});/d' "$FUNCTIONS_FILE" || true
  fi
fi  # end STATIC_PRESENT

FUNCTIONS_FILE_UPDATE="$CHILD_PATH/functions.php"
# ---------- Custom Code Additions ----------
echo "🛠️ Adding custom code snippets to child theme..."
# Append custom query modification if not already present
if ! grep -q "pre_get_posts.*programs" "$FUNCTIONS_FILE_UPDATE"; then
  cat >> "$FUNCTIONS_FILE_UPDATE" <<'PHP'

/**
 * Limit and order "programs" archive query
 */
add_action('pre_get_posts', function($query) {
    if (!is_admin() && $query->is_main_query() && is_post_type_archive('programs')) {
        $query->set('posts_per_page', 6);
        $query->set('meta_key', 'rank');
        $query->set('orderby', 'meta_value_num');
        $query->set('order', 'ASC');
    }
});
/**
 * Limit and order "instructors" archive query
 */
add_action('pre_get_posts', function($query) {
    if (!is_admin() && $query->is_main_query() && is_post_type_archive('instructors')) {
	$query->set('posts_per_page', 6);
	$query->set('meta_key', 'rank');
	$query->set('orderby', 'meta_value_num');
	$query->set('order', 'ASC');
    }
});
PHP
  echo "✅ Added pre_get_posts hook for 'programs' archive in functions.php"
else
  echo "ℹ️ pre_get_posts hook for 'programs' already exists in functions.php"
fi


# --- Add initial custom CSS if not already present ---
if ! grep -q "/* === Custom Initial CSS === */" "$STYLE_FILE"; then
  cat >> "$STYLE_FILE" <<'CSSINIT'

/* === Custom Initial CSS === */
.text-center {
  text-align: center;
}

.archive-programs-container {
  .main-heading {
    min-height: 250px;
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    margin-bottom: 30px;
    background: linear-gradient(35deg, #000, #333);
    isolation: isolate;
    h1 {
      font-size: 3rem;
      font-weight: bold;
      background: linear-gradient(135deg, #f06, #4a90e2);
      background-size: cover;
      background-position: center;
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      position: relative;
      &::before {
        content: "";
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        width: 110%;
        height: 110%;
        background-color: #fff;
        border-radius: 10px;
        z-index: -1;
      }
    }
  }
}

@media (width > 1200px) {
  #content {
    &.archive-programs {
      max-width: 1440px;
    }
  }
}

.archive-programs {
  > h1 {
    margin-bottom: 40px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 30px;
    background-color: var(--wp--preset--color--vivid-red);
    color: #fff;
    border-radius: 5px;
    @media (width < 600px) {
      font-size: 1.6rem;
    }
  }
  .programs-list {
    display: grid;
    /* grid-template-columns: repeat(auto-fit, minmax(370px, 1fr)); */
    grid-template-columns: 1fr;
    gap: 20px;
    .program-card {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      .content-wrapper {
        display: flex;
        align-items: flex-start;
        justify-content: center;
        flex-direction: column;
        height: 100%;
        padding: 40px;
      }
      &.even {
        direction: rtl;
        .content-wrapper {
          direction: ltr;
        }
      }

      .program-thumbnail {
        width: 100%;
        height: 550px;
        display: flex;
        align-items: center;
        justify-content: center;
        a {
          width: 100%;
          height: 100%;
          img {
            height: 100%;
            width: 100%;
            object-fit: cover;
            object-position: top;
            border-radius: 10px;
          }
        }
      }
      .program-excerpt {
        p {
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
      }
    }
    .learn-more-button {
      display: inline-block;
      padding: 10px 20px;
      background-color: var(--wp--preset--color--vivid-red);
      color: #fff;
      border-radius: 5px;
      text-decoration: none;
      border: 2px solid var(--wp--preset--color--vivid-red);
      transition: all 0.3s ease;
      &:hover {
        background-color: transparent;
        color: var(--wp--preset--color--vivid-red);
        text-decoration: none;
      }
    }
  }
  .pagination {
    max-width: 650px;
    margin-top: 50px;
    justify-content: center;
    gap: 20px;
    a {
      padding: 10px 20px;
      background-color: var(--wp--preset--color--vivid-red);
      color: #fff;
      border-radius: 5px;
      &:hover {
        background-color: var(--wp--preset--color--vivid-red);
        color: #fff;
        text-decoration: none;
      }
    }
    span {
      padding: 10px 20px;
      background-color: var(--wp--preset--color--cyan-bluish-gray);
      color: #fff;
      font-weight: bold;
      border-radius: 5px;
    }
    @media (width< 600px) {
      flex-wrap: wrap;
      justify-content: center;
      gap: 10px;
    }
  }
}

/* Single Programs */

#content {
  &.single-programs {
    img {
      width: 100%;
    }
  }
}

/* === End Custom Initial CSS === */

CSSINIT
  echo "✅ Initial custom CSS added to style.css"
else
  echo "ℹ️ Initial custom CSS already present, skipping."
fi

# ---------- Custom Page Template ----------
echo "📄 Creating custom page template in child theme..."

CHILD_PATH="$WP_PATH/wp-content/themes/hello-elementor-child"

# Ensure the child theme folder exists
mkdir -p "$CHILD_PATH"

# List of files you want to create
FILES=("single-programs.php" "archive-programs.php" "archive-instructors.php" "single-instructors.php")

for f in "${FILES[@]}"; do
  case "$f" in
    "single-programs.php")
      cat > "$CHILD_PATH/$f" <<'PHP'
<?php
get_header();

if (have_posts()) :
  while (have_posts()) : the_post(); ?>
    <main id="content" <?php post_class( 'site-main single-programs' ); ?>>
      <article <?php post_class('programs-single'); ?>>
        <header class="entry-header">
          <?php if (apply_filters('hello_elementor_page_title', true)) : ?>
            <div class="page-header">
              <?php the_title('<h1 class="entry-title">', '</h1>'); ?>
            </div>
          <?php endif; ?>
        </header>

        <div class="entry-content">
          <?php the_content(); ?>
        </div>

        <?php if (function_exists('get_field')) :
          $name = get_field('name');
          $body_content      = get_field('body_content');
          $banner     = get_field('program_banner');
        ?>
          <section class="program-meta">
            <?php if ($body_content): ?>
              <?php echo $body_content; ?>
            <?php endif; ?>
          </section>

          <?php if ($banner && !empty($banner['ID'])):
            echo wp_get_attachment_image($banner['ID'], 'large', false, ['class' => 'program-banner']);
          endif; ?>

          <?php if (function_exists('have_rows') && have_rows('modules')) : ?>
            <section class="program-modules">
              <h2>Modules</h2>
              <ul>
                <?php while (have_rows('modules')) : the_row();
                  $mod_title = get_sub_field('title');
                  $mod_desc  = get_sub_field('description'); ?>
                  <li>
                    <?php if ($mod_title) echo '<strong>' . esc_html($mod_title) . ':</strong> '; ?>
                    <?php if ($mod_desc)  echo esc_html($mod_desc); ?>
                  </li>
                <?php endwhile; ?>
              </ul>
            </section>
          <?php endif; ?>

        <?php else: ?>
          <p><em>ACF is not active or fields not found.</em></p>
        <?php endif; ?>
      </article>
    </main>
<?php endwhile;
endif;

get_footer();
?>
PHP
      ;;
    "archive-programs.php")
      cat > "$CHILD_PATH/$f" <<'PHP'
<?php
get_header(); 
if (have_posts()) :
?>
<div class="archive-programs-container">
<div class="main-heading">
<?php
the_archive_title('<h1 class="entry-title text-center">', '</h1>');
?>
</div>
<main id="content" class="site-main archive-programs">
<?php
$post_count = 0; // Initialize counter
echo '<div class="programs-list">'; 

while (have_posts()) : the_post(); 
    $is_even = ($post_count % 2 === 0);

?>
        <div class="program-card <?php echo $is_even ? 'even' : 'odd'; ?>">
                
        <?php if (has_post_thumbnail()) : ?>
                <div class="program-thumbnail">
                        <a href="<?php the_permalink(); ?>">
                                <?php the_post_thumbnail('large'); ?>
                        </a>
                </div>
        <?php endif; ?>

        
        <div class="content-wrapper">
                <h2 class="program-title">
                        <a href="<?php the_permalink(); ?>"><?php the_title(); ?></a>
                </h2>

                
                <div class="program-excerpt">
                        <?php the_excerpt(); ?>
                </div>

                <div class="learn-more-wrapper">
                        <a class="learn-more-button" href="<?php the_permalink(); ?>">Learn More</a>
                </div>
        </div>

        
        <?php
        if (function_exists('get_field')) {
                $first_name = get_field('first_name');
                if ($first_name) {
                        echo '<p><strong>First Name:</strong> ' . esc_html($first_name) . '</p>';
                }
        }
        ?>

        </div>
<?php     $post_count++; // Increment counter
 endwhile;

        echo '</div>'; 
        echo '<div class="pagination">';
        echo paginate_links([
                'prev_text' => '&laquo; Previous',
                'next_text' => 'Next &raquo;',
        ]);
        echo '</div>';
?>
</main>

<?php
else :
        echo '<h2 class="text-center">No programs found.</h2>';
endif;
?>
</div>
<?php
get_footer(); 
?>
PHP
      ;;
"archive-instructors.php")
      cat > "$CHILD_PATH/$f" <<'PHP'
<?php
get_header(); 
if (have_posts()) :
?>
<div class="archive-programs-container">
<div class="main-heading">
<?php
the_archive_title('<h1 class="entry-title text-center">', '</h1>');
?>
</div>
<main id="content" class="site-main archive-programs">
<?php
$post_count = 0; // Initialize counter
echo '<div class="programs-list">'; 

while (have_posts()) : the_post(); 
    $is_even = ($post_count % 2 === 0);

?>
        <div class="program-card <?php echo $is_even ? 'even' : 'odd'; ?>">
                
        <?php if (has_post_thumbnail()) : ?>
                <div class="program-thumbnail">
                        <a href="<?php the_permalink(); ?>">
                                <?php the_post_thumbnail('large'); ?>
                        </a>
                </div>
        <?php endif; ?>

        
        <div class="content-wrapper">
                <h2 class="program-title">
                        <a href="<?php the_permalink(); ?>"><?php the_title(); ?></a>
                </h2>

                
                <div class="program-excerpt">
                        <?php the_excerpt(); ?>
                </div>

                <div class="learn-more-wrapper">
                        <a class="learn-more-button" href="<?php the_permalink(); ?>">Learn More</a>
                </div>
        </div>

        
        <?php
        if (function_exists('get_field')) {
                $first_name = get_field('first_name');
                if ($first_name) {
                        echo '<p><strong>First Name:</strong> ' . esc_html($first_name) . '</p>';
                }
        }
        ?>

        </div>
<?php     $post_count++; // Increment counter
 endwhile;

        echo '</div>'; 
        echo '<div class="pagination">';
        echo paginate_links([
                'prev_text' => '&laquo; Previous',
                'next_text' => 'Next &raquo;',
        ]);
        echo '</div>';
?>
</main>

<?php
else :
        echo '<h2 class="text-center">No programs found.</h2>';
endif;
?>
</div>
<?php
get_footer(); 
?>
PHP
  ;;
"single-instructors.php")
      cat > "$CHILD_PATH/$f" <<'PHP'
<?php
get_header();

if (have_posts()) :
  while (have_posts()) : the_post(); ?>
    <main id="content" <?php post_class( 'site-main single-programs' ); ?>>
      <article <?php post_class('programs-single'); ?>>
        <header class="entry-header">
          <?php if (apply_filters('hello_elementor_page_title', true)) : ?>
            <div class="page-header">
              <?php the_title('<h1 class="entry-title">', '</h1>'); ?>
            </div>
          <?php endif; ?>
        </header>

        <?php if (has_post_thumbnail()) : ?>
            <div class="program-thumbnail">
                <a href="<?php the_permalink(); ?>">
                    <?php the_post_thumbnail('large'); ?>
                </a>
            </div>
        <?php endif; ?>

        <div class="entry-content">
          <?php the_content(); ?>
        </div>

        <?php if (function_exists('get_field')) :
          $name = get_field('name');
          $body_content      = get_field('biography');
          $banner     = get_field('program_banner');
        ?>
          <section class="program-meta">
            <?php if ($body_content): ?>
              <?php echo $body_content; ?>
            <?php endif; ?>
          </section>

          <?php if ($banner && !empty($banner['ID'])):
            echo wp_get_attachment_image($banner['ID'], 'large', false, ['class' => 'program-banner']);
          endif; ?>

          <?php if (function_exists('have_rows') && have_rows('modules')) : ?>
            <section class="program-modules">
              <h2>Modules</h2>
              <ul>
                <?php while (have_rows('modules')) : the_row();
                  $mod_title = get_sub_field('title');
                  $mod_desc  = get_sub_field('description'); ?>
                  <li>
                    <?php if ($mod_title) echo '<strong>' . esc_html($mod_title) . ':</strong> '; ?>
                    <?php if ($mod_desc)  echo esc_html($mod_desc); ?>
                  </li>
                <?php endwhile; ?>
              </ul>
            </section>
          <?php endif; ?>

        <?php else: ?>
          <p><em>ACF is not active or fields not found.</em></p>
        <?php endif; ?>
      </article>
    </main>
<?php endwhile;
endif;

get_footer();
?>
PHP
      ;;
  esac
  echo "✅ Created $CHILD_PATH/$f"
done

if [ "${INSECURE_PERMS:-0}" = "1" ]; then
  # ---------- Permissions (INSECURE: local dev only) ----------
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
  echo "⚠️ Setting INSECURE permissions (777) on $WP_PATH — local dev only!"
  $SUDO chmod -R 777 "$WP_PATH"
  echo "✅ Done (but consider switching to safe perms before going live)."
else
  # ---------- Permissions (recommended) ----------
  # Detect a likely web user; override by exporting WEB_USER if needed
  WEB_USER="${WEB_USER:-$(ps -o user= -C apache2 2>/dev/null | head -n1)}"
  WEB_USER="${WEB_USER:-$(ps -o user= -C httpd   2>/dev/null | head -n1)}"
  WEB_USER="${WEB_USER:-$(ps -o user= -C nginx   2>/dev/null | head -n1)}"
  WEB_USER="${WEB_USER:-www-data}"   # fallback for Debian/Ubuntu

  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

  echo "🔐 Setting recommended permissions for $WP_PATH (owner: $WEB_USER)"
  $SUDO chown -R "$WEB_USER:$WEB_USER" "$WP_PATH"

  # Directories 755, files 644
  find "$WP_PATH" -type d -exec $SUDO chmod 755 {} \;
  find "$WP_PATH" -type f -exec $SUDO chmod 644 {} \;

  # Allow uploads to be group-writable (helpful for CLI + web user collaboration)
  $SUDO chmod -R 775 "$WP_PATH/wp-content"
  $SUDO find "$WP_PATH/wp-content" -type f -exec chmod 664 {} \;

  # Tighten sensitive files
  $SUDO chmod 640 "$WP_PATH/wp-config.php" 2>/dev/null || true
  $SUDO chmod 640 "$WP_PATH/.htaccess"     2>/dev/null || true
  echo "✅ Permissions hardened."
fi

# 6) Flush caches
wp cache flush --allow-root || true

echo "✅ WordPress installed successfully at $WP_URL"
[ "$STATIC_PRESENT" -eq 1 ] && echo "✅ Static site imported and CSS bundled." || echo "ℹ️ Static site import skipped."
