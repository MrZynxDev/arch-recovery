# Dynamic desktop colors

Set a wallpaper and regenerate every integrated application with:

```sh
~/.config/theme/bin/set-wallpaper /path/to/image
```

Writing an absolute image path to `~/.config/theme/current-wallpaper` also triggers the systemd path unit. Changes made directly with `awww img` are detected by `dynamic-theme-watch.service` within two seconds. Matugen templates are in `~/.config/matugen/templates`; generated files should not be edited by hand.
