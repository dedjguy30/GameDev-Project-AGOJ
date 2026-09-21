extends Node


@onready var button_click = $button_click
@onready var card_combine = $card_combine
@onready var bgst1 = $bgst1
@onready var bgst2 = $bgst2
@onready var menoust = $menuost
# untuk nambah sfx, tambahin aja dilist atas

func play_sound(key):
	var sound = get(key)
	if sound is AudioStreamPlayer:
		sound.play()
	else:
		print("Sound " + key + " not found!")
		
		
