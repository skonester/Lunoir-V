module main

// The app is versioned separately from the v_mpv binding's v.mod manifests.
const app_version = $embed_file('../VERSION').to_string().trim_space()

fn app_about_text() string {
	return 'Lunoir V ${app_version}\nBased on Lunoir 0.9.4 by Yao666 (MIT) · Flet/Flutter · V libmpv binding (GPL-3.0-or-later)\ngithub.com/skonester/Lunoir-V'
}
