# Instación

## Gestor de sesiones

```sh
sudo systemctl enable sddm
sudo systemctl start sddm
```

## Docker

```sh
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
```

## Cambiar shell

- Cambiar shell de usuario a nushell

## Cambiar fondo en Hyprland

Edita el archivo hyprpaper.conf:

```sh
nano ~/.config/hypr/hyprpaper.conf
```

Contenido de ejemplo:

```sh
preload = /home/diegosi/Pictures/wallpapers/fondo.jpg
wallpaper = eDP-1,/home/diegosi/Pictures/wallpapers/fondo.jpg
```

- Asegúrate de reemplazar eDP-1 por el nombre real de tu pantalla.

- Puedes ver el nombre con:

```sh
hyprctl monitors
```

añadir qt6-multimedia

pasos para editar el grub

pasos para editar el sddm theme

## Editar el cursor

- Descarga el arcihvo de cursores [macOS-Monterey-White](https://www.pling.com/p/1648129)

```sh
tar -xvf macOS-Monterey-White.tar.gz
cp -r macOS-Monterey-White ~/.local/share/icons
cp -r macOS-Monterey-White /usr/share/icons
```

mostrar los pasos para instalar neovim y zellij
