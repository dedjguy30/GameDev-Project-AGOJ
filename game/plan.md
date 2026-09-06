# PLAN — SPACE SALVAGE (working title)

> **Master dokumen proyek.** Berisi desain game lengkap (GDD v2), struktur folder, roadmap implementasi, dan progress log.
> Sumber desain: `C:\Users\notsomnia\Downloads\GDD_Space_Salvage.md` (v2 — akan terus di-update, plan.md ini ikut di-sync).

Resource Management ala **Stacklands**, tema Astronot/Penjelajah Galaksi Terdampar — Engine: **Godot 4.7** (GDScript, GL Compatibility, 2D).

---

# BAGIAN A — DESAIN GAME (GDD v2, lengkap)

## A0. GLOSARIUM CEPAT

| Istilah | Arti |
|---|---|
| Card | Objek dasar di board, semua "benda" di game ini adalah Card |
| Board | Area drag-and-drop utama tempat semua Card diletakkan |
| Node | Card statis sumber daya mentah (mis. Asteroid Field) — bukan Unit, bukan resource item |
| Unit | Card karakter/pekerja yang bisa di-drag ke Node/Building/Package untuk bekerja |
| Item | Card resource yang bisa ditumpuk (stack) di inventory/board: Raw, Processed, Food, dll |
| Day/Tick | 1 siklus waktu game, dipicu tombol "End Day" |
| Combine | Aksi drag 1 card ke card lain untuk memicu crafting/recipe |

## A1. CORE LOOP

```
[Board State: Node cards, Item cards, Building cards, Unit cards tersebar]
		↓
Player drag Unit → Node/Building/Package  →  Unit mulai kerja (state: Working)
		↓
Player drag Item + Item (atau Item + Building) → cek Recipe table → jika match → spawn Output card
		↓
Player rakit Package (isi requirement) → kirim ke Sektor → dapat Credits + Rep
		↓
Player klik "End Day" → jalankan Tick Resolution (lihat A15) → stat berubah, event random muncul
		↓
Ulangi. Game over jika O2=0 berkepanjangan / semua Unit mati / Hull=0
```

## A1.1 BOARD / PLAYMAT LAYOUT

Playmat adalah **satu board tunggal, dibagi visual jadi 2 zona** (bukan 2 board terpisah, tidak ada loading/switch screen).

```
┌─────────────────────────┬─────────────────────────┐
│   ZONA KAPAL (kiri)      │   ZONA ANGKASA (kanan)   │
│   Ship Interior           │   Open Space / Sector     │
│                           │                           │
│  - Building slot          │  - Node card (gather)     │
│  - Unit idle/assign       │  - Event card muncul di   │
│  - Card Pack opening area │    sini (visual)          │
│  - Package assembly       │  - Titik keberangkatan    │
│    (dekat Cargo Bay)      │    Package ke sektor lain │
└─────────────────────────┴─────────────────────────┘
		↑ garis batas kosmetik (airlock) ↑
   Unit bebas di-drag nyebrang kedua zona kapan saja
```

### Rules

- **Building** hanya bisa ditempatkan/dibangun di **Zona Kapal**.
- **Node** hanya muncul/spawn di **Zona Angkasa**.
- **Unit** bebas dipindah ke zona manapun. Drag Unit dari Zona Kapal → Node di Zona Angkasa = "keluar EVA buat gathering". Drag balik ke Zona Kapal = "masuk kapal lagi". Untuk v1 tidak ada cost tambahan buat nyebrang zona (opsi EVA Suit requirement sebagai penyeimbang ada di A18, belum diputuskan untuk v1).
- **Package** dirakit di Zona Kapal (dekat Building Cargo Bay), lalu "diberangkatkan" dengan drag Unit(role: Pilot lebih baik) + Package ke titik keberangkatan di ujung Zona Angkasa → memicu state TRAVELING (lihat A4, A8).
- **Stat Ship** (O2, Food, Hull, Power) ditampilkan sebagai HUD tetap di atas board (bukan card, bukan milik satu zona) — berlaku global untuk seluruh kapal.
- Zona Angkasa bisa melebar/scroll seiring Node baru ditemukan (progres eksplorasi sektor). Zona Kapal melebar seiring Building baru dibangun (opsional, tuning lanjut — lihat A18).

```gdscript
enum BoardZone { SHIP_INTERIOR, OPEN_SPACE }
# dipakai board manager untuk validasi drop:
#   BuildingCardData → hanya boleh drop di SHIP_INTERIOR
#   NodeCardData      → hanya spawn di OPEN_SPACE
#   UnitCardData      → boleh drop di kedua zona, TAPI lihat A1.2 untuk syarat masuk OPEN_SPACE
```

## A1.2 SISTEM O2 TETHER (EVA Connection)

Setiap Unit yang mau kerja di Zona Angkasa (gather di Node) butuh koneksi oksigen ke kapal — divisualisasikan sebagai **kabel/tether** yang menyambung dari card Unit ke Building **O2 Umbilical Station** di Zona Kapal.

### Rule

- **O2 Umbilical Station** adalah Building (lihat A7) dengan field `max_connections`.
- Saat Unit di-drag dari Zona Kapal ke Zona Angkasa, sistem cek slot kosong di O2 Umbilical Station manapun yang sudah dibangun:
  - Ada slot kosong → Unit jadi **connected** (tether tervisualisasi sebagai garis kabel dari card Unit ke card Station), boleh WORKING normal di Node manapun di Zona Angkasa.
  - Tidak ada slot kosong → drag ditolak, KECUALI Unit itu sedang equip Tool **Portable O2 Tank** (lihat A6).
- Unit connected otomatis **disconnect** (slot kebuka lagi) begitu ditarik balik ke Zona Kapal.
- Kalau Station kehilangan Power (misal event Solar Flare) sementara ada Unit connected → semua Unit yang connected ke Station itu berstatus **O2 Cut** sampai Power nyala lagi atau Unit ditarik balik ke kapal.

### Formula

```
max_units_outside_bersamaan = Σ max_connections(semua O2 Umbilical Station terbangun & berdaya)

on_drag_unit_to_open_space(unit):
	if unit.has_tool("portable_o2_tank"):
		allow, tank_remaining_days -= 1 tiap End Day selagi di luar
	elif units_connected_saat_ini < max_units_outside_bersamaan:
		allow, unit.is_tethered = true
	else:
		reject_drag("butuh slot O2 Umbilical Station kosong")

tiap End Day:
	if unit.is_tethered and station_terkait.has_power() == false:
		unit.status = O2_CUT
	if unit.has_tool("portable_o2_tank") and tank_remaining_days <= 0:
		unit.status = O2_CUT

	if unit.status == O2_CUT:
		# pakai formula kematian yang sama seperti global O2=0 di A14
		25% chance unit → DEAD, tiap hari selama status O2_CUT bertahan

	if unit kembali ke Zona Kapal:
		unit.is_tethered = false
		unit.status = NORMAL
		tank_remaining_days = reset ke default (recharge otomatis saat di kapal)
```

## A2. KATEGORI CARD (Card Type Enum)

```gdscript
enum CardCategory {
	NODE,           # sumber daya mentah statis
	ITEM_RAW,       # resource mentah, stackable
	ITEM_PROCESSED, # resource olahan, stackable
	ITEM_FOOD,      # consumable, stackable
	TOOL,           # equipment, biasanya dipasang ke Unit/dipakai sekali
	BUILDING,       # struktur produksi pasif, tidak bisa dipindah setelah dibangun
	UNIT,           # karakter pekerja, bisa displace/di-drag
	PACKAGE,        # quest delivery card
	EVENT,          # kartu event/threat, muncul otomatis, bukan hasil drag player
	CURRENCY_LOOT,  # Credits, Artifact — hasil jual/reward
}
```

Semua card mewarisi base schema ini:

```gdscript
# CardData.gd — base Resource untuk SEMUA card
class_name CardData extends Resource
@export var id: String              # unique key, mis. "node_asteroid_field"
@export var display_name: String
@export var category: CardCategory
@export var rarity: Rarity          # COMMON, UNCOMMON, RARE, EPIC
@export var icon: Texture2D
@export var description: String
@export var stack_max: int = 99     # khusus ITEM_*, 0 kalau non-stackable
@export var sell_value: int = 0
```

## A3. NODE CARD (sumber daya mentah — statis di board)

Node BUKAN item, BUKAN unit. Node adalah "tempat" yang di-drag Unit ke atasnya untuk memicu gather otomatis berulang (mirip Tree/Rock/Bush di Stacklands).

> **Zona:** Node hanya muncul/spawn di **Zona Angkasa (kanan)** — lihat A1.1.

```gdscript
# NodeCardData.gd extends CardData
@export var output_item_id: String       # id ITEM yang di-spawn tiap panen
@export var gather_interval_sec: float   # base waktu 1x panen (real-time, sesuai Stacklands-style)
@export var output_qty: int = 1
@export var is_limited: bool = false     # true = punya durability (habis), false = infinite
@export var durability: int = 0          # dipakai hanya kalau is_limited = true, berkurang tiap panen
@export var max_unit_slots: int = 1      # berapa Unit bisa kerja bareng di 1 node (percepat linear)
```

### Tabel Node

| Node Card | Output | Interval Dasar | Infinite/Limited | Slot Unit |
|---|---|---|---|---|
| Asteroid Field | Space Ore | 8s | Infinite (tapi ada regen-delay, lihat formula) | 2 |
| Debris Field | Scrap Metal | 5s | Infinite | 2 |
| Ice Field | Ice Chunk | 6s | Limited, durability = 15 | 1 |
| Gas Cloud | Space Gas | 10s | Infinite, **butuh Tool: Cutting Laser terpasang di Unit** sebelum bisa gather | 1 |
| Alien Ruins | Alien Flora / Crystal Ore (50/50) | 12s | Limited, durability = 8 | 1 |

### Formula Gather

```
effective_interval = gather_interval_sec / unit_efficiency
unit_efficiency: Astronaut = 1.0, Engineer_di_node_mining = 1.5, Specialist_lain = 1.0

# tiap effective_interval detik selagi Unit berstatus WORKING di node ini:
spawn_item(output_item_id, output_qty) di slot kosong terdekat pada board

if node.is_limited:
	node.durability -= 1
	if node.durability <= 0:
		remove_node_from_board()   # node hilang, Unit otomatis jadi IDLE

# node infinite tetap boleh diberi "regen-delay" opsional supaya tidak dispam:
regen_delay_after_burst = 0 (default off, bisa dituning kalau perlu balancing lanjutan)
```

Alien Ruins hanya muncul di board lewat: Event `Alien Encounter` (opsi "explore"), atau random spawn saat pindah ke sektor baru.

## A4. UNIT CARD (pekerja, statis-tapi-bisa-dipindah)

Satu kategori Unit dipakai untuk SEMUA jenis pekerja (bukan sub-card berbeda). Unit dibedakan lewat field `role`.

```gdscript
# UnitCardData.gd extends CardData
@export var role: UnitRole   # GENERALIST, ENGINEER, SCIENTIST, PILOT, ROBOT_DRONE
@export var role_efficiency_map: Dictionary  # { "node_asteroid_field": 1.5, "building_smelter": 2.0, ... }
@export var needs_food: bool = true          # false untuk Robot Drone
@export var needs_oxygen: bool = true        # false untuk Robot Drone
@export var needs_power_to_work: bool = false # true untuk Robot Drone
# runtime state (bukan @export, di-track saat gameplay):
var is_tethered: bool = false        # true kalau connected ke O2 Umbilical Station, lihat A1.2
var tether_status: TetherStatus = TetherStatus.NORMAL  # NORMAL, O2_CUT
```

### Unit State Machine

```
enum UnitState { IDLE, WORKING, TRAVELING, DEAD }

IDLE      → default, tergeletak bebas di board, bisa di-drag kemanapun
WORKING   → sedang ditempel ke Node / Building / assemble Package, jalankan gather/produksi loop
TRAVELING → sedang membawa Package ke sektor tujuan (tidak bisa dipakai sampai sampai tujuan)
DEAD      → dihapus dari board, tidak bisa dipakai lagi

Transisi:
  drag Unit ke Node/Building/Package     → IDLE atau WORKING → WORKING (di target baru)
  drag Unit menjauh dari target          → WORKING → IDLE
  assign Unit sebagai Pilot pengantar    → WORKING/IDLE → TRAVELING, otomatis balik IDLE setelah travel_days selesai
  O2/Food = 0 berkepanjangan (lihat A14) → WORKING/IDLE → DEAD
```

Recruit Unit baru lewat **Recruit Pack** (lihat A12) atau event rescue.

### A4a. PROMOSI ROLE (keputusan v2.1)

Semua Unit yang direkrut **selalu mulai sebagai Astronaut (GENERALIST)**. Role spesialis (Engineer/Scientist/Pilot) didapat dengan **promosi**: drag (combine) kartu Astronaut + item tertentu → kartu berubah jadi role baru (posisi tetap di board, konsumsi item).

| Promosi | Combine (input) | Syarat | Output |
|---|---|---|---|
| Engineer | Astronaut ×1 + Circuit Board ×2 | Workshop terbangun | Engineer ×1 |
| Scientist | Astronaut ×1 + Alien Flora ×1 | Workshop terbangun | Scientist ×1 |
| Pilot | Astronaut ×1 + Fuel Cell ×2 | Workshop terbangun | Pilot ×1 |

- Robot Drone **bukan** promosi — tetap di-craft langsung dari item (Circuit Board ×3 + Metal Ingot ×2).
- Data: 3 resep promosi (`recipe_promote_engineer|scientist|pilot`) dengan `required_building_id = "building_workshop"`, durasi instan. Diproses oleh Combine Engine (A13) sama seperti resep biasa.
- Jika promosi di-revert/putus (belum diputuskan, open question), lihat Bagian E.

## A5. ITEM CARD (Raw / Processed / Food) — stackable, hasil gather/craft

```gdscript
# ItemCardData.gd extends CardData
@export var item_type: ItemType   # RAW, PROCESSED, FOOD
@export var food_restore: int = 0 # khusus FOOD
```

### A5a. Raw Resource (hasil panen Node, lihat A3 untuk sumbernya)

| Item | Sumber Node | Rarity |
|---|---|---|
| Space Ore | Asteroid Field | Common |
| Scrap Metal | Debris Field | Common |
| Ice Chunk | Ice Field | Common |
| Space Gas | Gas Cloud | Uncommon |
| Alien Flora | Alien Ruins | Rare |
| Crystal Ore | Alien Ruins | Epic |
| Meteorite Fragment | (bukan node — drop dari Event "Meteor Shower") | Rare |

### A5b. Processed Resource (hasil Combine 2 Item, atau produksi pasif Building)

| Output | Resep (Combine) | Cara Alternatif (pasif) |
|---|---|---|
| Water | Ice Chunk + "Heat Source" (Tool sekali pakai, atau Building Smelter aktif) | – |
| Oxygen Canister | Water + Power (otomatis, syarat Building = Oxygen Generator berdiri & ada Unit WORKING di situ) | pasif harian |
| Metal Ingot | Space Ore ×2 (drag stack ke stack) | pasif via Smelter + Unit WORKING |
| Fuel Cell | Space Gas ×2 | pasif via Fuel Refinery + Unit WORKING |
| Circuit Board | Scrap Metal ×2 + Crystal Ore ×1 | manual combine saja |
| Alien Extract | Alien Flora ×1 | pasif via Science Lab + Scientist WORKING |

### A5c. Food

| Item | Resep/Sumber | Food Restore |
|---|---|---|
| Ration Pack | Loot awal / Salvage Pack | 20 |
| Hydro Veggie | pasif via Hydroponics Bay + Unit WORKING (butuh Water sebagai input harian) | 15 |
| Protein Paste | Alien Extract + "Processor" (Tool) | 25 |
| Feast Meal | Hydro Veggie ×3 + Protein Paste ×1 (butuh Unit role apapun WORKING di Building Kitchen) | 60 (+Morale 10) |

## A6. TOOL CARD

Tool dipasang (equip) ke Unit lewat drag Tool→Unit, atau dipakai sekali habis (consumable) tergantung `is_consumable`.

```gdscript
# ToolCardData.gd extends CardData
@export var effect_type: ToolEffect  # UNLOCK_GATHER, SPEED_BOOST, REPAIR, CRAFT_UNLOCK
@export var effect_value: float
@export var is_consumable: bool = false
```

| Tool | Resep | Efek |
|---|---|---|
| Mining Drill | Scrap Metal ×3 (butuh Engineer WORKING saat combine) | Equip ke Unit → gather di Asteroid Field 2× lebih cepat |
| Welding Torch | Scrap Metal ×2 + Fuel Cell ×1 | Prasyarat untuk craft Repair Kit |
| Scanner | Circuit Board ×1 + Scrap Metal ×2 | Reveal Package tersembunyi / Node tersembunyi di sektor |
| Cutting Laser | Metal Ingot ×2 + Circuit Board ×1 | Equip ke Unit → wajib dipakai sebelum bisa gather Gas Cloud |
| Repair Kit | Scrap Metal ×2 + Welding Torch ×1 | Consumable, pakai ke kartu Ship/Hull → Hull +20 |
| Portable O2 Tank | Metal Ingot ×2 + Fuel Cell ×1 | Equip ke Unit → boleh kerja di Zona Angkasa tanpa slot O2 Umbilical Station, tapi cuma tahan `tank_duration_days` (default 3 hari) sebelum Unit harus balik ke kapal buat recharge — lihat A1.2 |

## A7. BUILDING CARD

Building ditempatkan (bukan stackable), butuh Power untuk aktif, dan butuh minimal 1 Unit berstatus WORKING di situ supaya produksi jalan (kecuali disebutkan lain).

> **Zona:** Building hanya bisa ditempatkan di **Zona Kapal (kiri)** — lihat A1.1.

```gdscript
# BuildingCardData.gd extends CardData
@export var build_cost: Array[ItemRequirement]  # [{item_id, qty}, ...]
@export var power_draw: int
@export var max_unit_slots: int = 1
@export var production: ProductionRule   # {input_item_id/qty (opsional), output_item_id, qty, interval_days=1}
@export var passive_effect: String = ""  # untuk building non-produksi (Cargo Bay, Trade Post, dst)
```

| Building | Build Cost | Power Draw | Produksi/Efek per Hari (butuh Unit WORKING) |
|---|---|---|---|
| Hydroponics Bay | Metal Ingot ×3 + Water ×2 | 5 | Water → Hydro Veggie |
| Oxygen Generator | Metal Ingot ×3 + Circuit Board ×1 | 8 | Water → Oxygen Canister → otomatis dipakai isi ulang O2 kapal |
| Smelter | Scrap Metal ×5 | 6 | Space Ore ×2 → Metal Ingot ×1 (otomatis kalau ada stok Ore) |
| Fuel Refinery | Metal Ingot ×4 + Circuit Board ×1 | 6 | Space Gas ×2 → Fuel Cell ×1 |
| Workshop | Metal Ingot ×5 | 4 | Unlock resep Tool tier-2 (tidak produksi item) |
| Science Lab | Metal Ingot ×4 + Crystal Ore ×1 | 10 | Alien Flora ×1 → Alien Extract ×1 |
| Cargo Bay | Scrap Metal ×6 | 0 | Pasif: +50% stack_max semua Item (tidak butuh Unit) |
| Solar Panel | Metal Ingot ×3 | 0 (generator, minus) | Pasif: +Power_generated harian (tidak butuh Unit) |
| Trade Post | Metal Ingot ×5 + Circuit Board ×1 | 3 | Buka fitur "Sell Item" jadi Credits |
| Med Bay | Metal Ingot ×4 + Alien Extract ×1 | 5 | Cegah 1 Unit mati/hari saat O2 atau Food kritis |
| O2 Umbilical Station | Metal Ingot ×4 + Circuit Board ×2 | 6 | Tidak produksi item — pasif: sediakan `max_connections` slot tether O2 buat Unit kerja di Zona Angkasa (lihat A1.2) |

## A8. PACKAGE CARD (quest delivery)

```gdscript
# PackageCardData.gd extends CardData
@export var destination_sector_id: String
@export var required_items: Array[ItemRequirement]
@export var reward_credits: int
@export var reward_rep: int
@export var deadline_days: int
@export var tier: int   # 1-3, pengaruh reward_multiplier
```

Alur:
```
1. Package card muncul di Zona Kapal, dekat Cargo Bay (auto-spawn via Comm Array, atau manual beli di Trade Post)
2. Player drag Item yang sesuai requirement ke Package card → item ter-"lock" ke package (qty berkurang dari stok)
3. Setelah semua requirement terpenuhi → drag Package + 1 Unit (idealnya Pilot) bareng ke titik keberangkatan
   di ujung Zona Angkasa (lihat A1.1) → Unit masuk state TRAVELING
4. Setelah travel_days berlalu (dihitung tiap End Day) → Package selesai:
	 grant reward_credits, reward_rep
	 Unit kembali ke Zona Kapal dengan state IDLE
```

### Formula Reward

```
reward_credits = Σ(sell_value(item) × qty) × delivery_multiplier
delivery_multiplier: Tier1=1.5, Tier2=2.0, Tier3=3.0

reward_rep = base_rep(tier) × timing_bonus
timing_bonus = 1.2 jika selesai ≤ 50% deadline_days
			 = 1.0 jika selesai tepat waktu
			 = 0.5 jika telat (tetap diterima)

travel_days = base_distance(sector_id) / (1 + pilot_bonus)
pilot_bonus = 0.5 jika Unit yang dikirim role == PILOT, else 0
```

### Tabel Sektor

| Sektor | Jarak Dasar (hari) | Rep Required Unlock | Reward Multiplier |
|---|---|---|---|
| Debris Field (starting) | 1 | 0 | 1.0 |
| Asteroid Belt | 2 | 20 | 1.5 |
| Gas Nebula | 3 | 50 | 2.0 |
| Alien Ruins Sector | 4 | 100 | 3.0 |
| Deep Void | 6 | 200 | 4.5 |

## A9. EVENT CARD (muncul otomatis, bukan hasil combine player)

```gdscript
# EventCardData.gd extends CardData
@export var effect_type: EventEffect  # DAMAGE_HULL, DAMAGE_O2, STEAL_RESOURCE, POWER_DEBUFF, BUFF_LOOT, PLAYER_CHOICE
@export var effect_value: float
@export var duration_days: int = 0     # 0 = instan, >0 = efek berlangsung X hari
@export var choices: Array[EventChoice] = []  # khusus PLAYER_CHOICE
```

| Event | Efek | Mitigasi |
|---|---|---|
| Asteroid Storm | Hull -15 instan | Repair Kit siap pakai |
| Hull Breach | Hull -10, O2 -10 instan | Engineer + Repair Kit cepat |
| Space Pirates | Curi 20% dari salah satu stack Item random | Defense Turret (building lanjutan, belum masuk v1) |
| Solar Flare | Power_generated -50% selama 1 hari | Cadangan Fuel Cell / battery |
| Meteor Shower | Spawn Meteorite Fragment ×3 di board (positif) | – |
| Alien Encounter | Player pilih: **Trade** (dapat Alien Pack gratis) / **Flee** (aman, no reward) | Keputusan manual |
| Engine Malfunction | Power_consumption +30% selama 2 hari | Stok Fuel Cell cadangan |

### Formula Kemunculan Event

```
P(event_muncul, hari ke-d) = clamp(0.15 + 0.01 × d, 0.15, 0.6)
event_terpilih = weighted_random(event_pool, weight = rarity_weight)
effect_value_aktual = base_effect_value × event_severity_multiplier(d)   # lihat A14
```

## A10. CURRENCY & SELL

**Credits** — dari reward Package, atau jual Item di Trade Post.
**Reputation (Rep)** — dari reward Package, dipakai unlock sektor baru & tier pack lebih tinggi.

```
sell_value(item) = base_value(item) × rarity_multiplier
rarity_multiplier: Common=1.0, Uncommon=1.5, Rare=2.5, Epic=4.0
```

## A11. SHIP / SURVIVAL STATS

| Stat | Awal | Max | Naik dari | Turun dari |
|---|---|---|---|---|
| Oxygen (O2) | 100 | 100 | Oxygen Canister (auto-consumed saat produksi Oxygen Generator) | Konsumsi harian kru |
| Food/Hunger | 100 | 100 | Makan Food item (auto-consumed End Day) | Konsumsi harian kru |
| Hull Integrity | 100 | 100 | Repair Kit | Event serangan |
| Power | 50 | tergantung total Solar Panel | Solar Panel, Fuel Cell (emergency) | Power_draw semua Building/Tool aktif |
| Morale (fase 2, opsional v1) | 100 | 100 | Feast Meal, event positif | Food/O2 kritis, Unit mati, Hull rusak |

## A12. CARD PACK & EKONOMI

| Pack | Harga Dasar (Credits) | Isi | Drop Table |
|---|---|---|---|
| Salvage Pack | 10 | 3 card | Raw Item 70%, Food 20%, Event ringan 10% |
| Tech Pack | 30 | 3 card | Processed Item 40%, Tool 30%, Circuit Board 20%, Rare item 10% |
| Recruit Pack | 50 | 1 Unit card | Generalist 50%, Engineer 20%, Scientist 20%, Pilot 10% |
| Alien Pack | 80 | 2 card | Alien Flora 40%, Crystal Ore 25%, Alien Extract 15%, Artifact Loot 20% |
| Mystery Pack (reward only, tidak dijual) | – | 1-4 card | Semua tier termasuk Epic |

```
harga_pack(n) = harga_dasar × (1 + 0.05 × n)   # n = jumlah pack tipe sama yang sudah dibeli sepanjang game

weight_total = Σ weight(item_kandidat)
P(item) = weight(item) / weight_total
weight_default: Common=100, Uncommon=45, Rare=15, Epic=5
```

## A13. COMBINE / CRAFTING — RULE ENGINE

Semua resep didefinisikan sebagai data (`.tres`), bukan hardcode, supaya gampang nambah konten.

```gdscript
# CraftRecipe.gd extends Resource
@export var inputs: Array[ItemRequirement]      # bisa Item, atau requirement "Unit dengan role tertentu WORKING"
@export var required_building_id: String = ""   # "" jika manual combine di board
@export var required_unit_role: UnitRole = UnitRole.ANY
@export var output_id: String
@export var output_qty: int = 1
@export var duration_days: int = 0   # 0 = instan (manual combine), >0 = perlu N hari (produksi Building)
```

### Tabel Ringkas Semua Resep

| Input | Building/Unit Prasyarat | Output |
|---|---|---|
| Ice Chunk + Heat Source(Tool) | – | Water |
| Water + Power | Oxygen Generator, Unit WORKING | Oxygen Canister |
| Space Ore ×2 | Smelter, Unit WORKING | Metal Ingot |
| Space Gas ×2 | Fuel Refinery, Unit WORKING | Fuel Cell |
| Scrap Metal ×2 + Crystal Ore ×1 | – (manual) | Circuit Board |
| Alien Flora ×1 | Science Lab, Scientist WORKING | Alien Extract |
| Scrap Metal ×3 | Engineer WORKING saat combine | Mining Drill |
| Scrap Metal ×2 + Fuel Cell ×1 | – | Welding Torch |
| Metal Ingot ×2 + Circuit Board ×1 | – | Cutting Laser |
| Circuit Board ×3 + Metal Ingot ×2 | – | Robot Drone (Unit baru) |
| Hydro Veggie ×3 + Protein Paste ×1 | Building "Kitchen" (sub-fungsi Hydroponics Bay), Unit WORKING | Feast Meal |
| Alien Extract ×1 + Processor(Tool) | – | Protein Paste |

Resolusi combine (manual, instan):
```
on_drag_drop(card_a, card_b):
	recipe = find_recipe_matching(card_a, card_b)   # cek dua arah, urutan tidak penting
	if recipe == null: return "no match, cards stay separate"
	if recipe.required_unit_role != ANY and no Unit(role=required_unit_role, state=WORKING nearby):
		return "blocked: butuh Unit role X"
	consume(recipe.inputs)
	spawn(recipe.output_id, recipe.output_qty)
```

## A14. FORMULA KONSUMSI & KEMATIAN

```
O2_consumption/hari    = 5 × jumlah_unit_hidup_yg_needs_oxygen
Food_consumption/hari  = 4 × jumlah_unit_hidup_yg_needs_food
Power_consumption/hari = Σ power_draw(building_aktif) + Σ power_draw(unit ROBOT_DRONE working)

O2_baru    = clamp(O2 - O2_consumption + O2_produced, 0, 100)
Food_baru  = clamp(Food - Food_consumption + Food_produced, 0, 100)
Power_baru = clamp(Power - Power_consumption + Power_generated, 0, Power_cap)

# jika Power_baru akan negatif: auto-shutdown building dengan power_draw tertinggi dulu,
# KECUALI Oxygen Generator & Med Bay (life support diprioritaskan tetap nyala)

if O2 == 0:
	tiap Unit(needs_oxygen=true, alive) punya 25% chance DEAD per hari
if Food == 0:
	Morale -10/hari
	if Food == 0 selama 3 hari berturut-turut: 1 Unit random → DEAD (Med Bay bisa cegah ini, lihat A7)
if Hull == 0:
	GAME OVER
```

## A15. TICK RESOLUTION — PSEUDOCODE "END DAY"

Ini fungsi utama yang dipanggil setiap player klik tombol End Day. Urutan penting untuk konsistensi.

```
func end_day():
	day += 1

	# 1. Resolve semua Building production yang duration_days habis
	for building in active_buildings:
		if building.has_unit_working() and has_power(building):
			resolve_production(building)   # consume input, spawn output sesuai A13

	# 2. Auto-consume Food untuk semua Unit hidup
	consume_food_stock(Food_consumption)

	# 3. Auto-consume/replenish O2 dari Oxygen Canister stock
	replenish_oxygen()

	# 4. Update stat utama sesuai formula A14
	update_stats(O2, Food, Power)

	# 5. Cek kematian/critical state
	resolve_critical_effects()

	# 6. Resolve Package yang sedang TRAVELING (kurangi travel_days_remaining, selesai kalau 0)
	resolve_traveling_packages()

	# 7. Roll random Event sesuai formula A9
	maybe_spawn_event(day)

	# 8. Apply difficulty scaling (lihat A16) ke variabel global
	apply_difficulty_scaling(day)

	# 9. Cek kondisi Game Over
	check_game_over()   # O2 berkepanjangan / semua Unit mati / Hull=0

	# 10. Update score berjalan
	update_score()
```

## A16. DIFFICULTY SCALING

```
Consumption_multiplier(day) = 1 + 0.02 × day
Event_severity_multiplier(day) = 1 + 0.015 × day
Package_reward_multiplier(day) = 1 + 0.01 × day
```
Dipakai sebagai pengali tambahan di formula A14 (konsumsi), A9 (efek event), A8 (reward package).

### Skor Akhir
```
Score = (total_days_survived × 100) + (total_credits_earned × 1) + (total_packages_delivered × 50)
```

---

# BAGIAN B — STRUKTUR FOLDER

## Target (sesuai GDD §17)

```
res://
  data/
	cards/
	  nodes/*.tres         # NodeCardData
	  items_raw/*.tres     # ItemCardData (RAW)
	  items_processed/*.tres
	  items_food/*.tres
	  tools/*.tres         # ToolCardData
	  buildings/*.tres     # BuildingCardData
	  units/*.tres         # UnitCardData
	recipes/*.tres         # CraftRecipe
	events/*.tres          # EventCardData
	packages/*.tres        # PackageCardData template per sektor
	sectors/*.tres         # SectorData (jarak, rep_required, reward_multiplier)
	packs/*.tres           # PackDefinition (harga_dasar, drop_table)
  scripts/
	core/
	  card_base.gd
	  card_types/ (node_card.gd, unit_card.gd, building_card.gd, ...)
	systems/
	  day_cycle_manager.gd   # implementasi A15
	  recipe_resolver.gd     # implementasi A13
	  economy_manager.gd     # pack, sell, credits — A10 A12
	  event_manager.gd       # A9
	  package_manager.gd     # A8
	  difficulty_manager.gd  # A16
	ui/
	  board_drag_drop.gd
	  hud_stats.gd
```

Prinsip: **semua angka/isi/resep ada di file `.tres`**, script cuma baca & eksekusi rule generik. Nambah kartu/resep/event baru = bikin file `.tres` baru, tidak perlu ubah script.

## Struktur saat ini (sudah ada — masih prototype, akan di-refactor)

```
game/
├── main.tscn              (scene utama — diset di project.godot)
├── scenes/card.tscn + card.gd    (kartu prototype: click/drag/stack — Phase 0)
├── scenes/stack.tscn + stack.gd  (pile/dropzone prototype — Phase 0)
└── scripts/main.gd        (spawn kartu test)
```

Catatan: prototype Phase 0 akan di-refactor menjadi sistem CardData (Resource) + board 2 zona sesuai bagian A.

## Prinsip Pengembangan — Placeholder Visual

- **Belum ada sprite/gambar apa pun.** Semua kartu memakai placeholder: panel berwarna + teks `display_name` (kayak prototype Phase 0: Panel + ColorRect + Label).
- Field `icon: Texture2D` di `CardData` dibiarkan kosong dulu (opsional), visual utama = warna + nama.
- Sprite/icon/gambar dikerjakan **terakhir** (bagian polish), saat semua sistem gameplay sudah jalan.
- Tiap card type boleh punya warna placeholder khas biar mudah dibedakan saat playtest (mis. Resource = abu, Food = oranye, Tool = biru, Building = ungu, Unit = hijau, dst).

---

# BAGIAN C — ROADMAP IMPLEMENTASI (urutan build satu-per-satu)

- [x] **Phase 0 — Fondasi kartu prototype:** click, drag, stack, pile (selesai, masih dipakai dasar interaksi)
- [x] **Phase 1 — Fondasi Data:** `CardData` + subclass (Node/Unit/Item/Tool/Building/Package/Event) sebagai Resource scripts, `CraftRecipe`, enum global (CardCategory, UnitRole, dll), autoload `GameState` + DB loader, dan file `.tres` data awal (nodes, items, tools, buildings, units, recipes, sectors, packs)
- [x] **Phase 2 — Board & Drag-Drop:** board 1 scene 2 zona (`SHIP_INTERIOR`, `OPEN_SPACE`), validasi drop per kategori, item stacking, visual card dari CardData
- [x] **Phase 3 — Combine Engine:** `recipe_resolver.gd`, manual combine instan (A13) — termasuk resep promosi role unit (A4a)
- [x] **Phase 4 — Node & Gather:** real-time gather interval, durability node, output spawn (A3)
- [x] **Phase 5 — Unit & State Machine:** role, IDLE/WORKING/TRAVELING/DEAD, efficiency map, kebutuhan food/O2/power (A4)
- [x] **Phase 6 — Building & Power:** build cost, power_draw, produksi harian, auto-shutdown prioritas (A7, A14)
- [x] **Phase 7 — Day Cycle:** `day_cycle_manager.gd` — End Day tick 10 langkah, konsumsi, kematian, difficulty scaling, game over (A14, A15, A16)
- [x] **Phase 8 — Ekonomi & Pack:** credits, sell di Trade Post, card pack + drop table, harga progresif (A10, A12)
- [x] **Phase 9 — Package & Sektor:** assembly requirement, keberangkatan TRAVELING, reward formula, unlock sektor (A8)
- [x] **Phase 10 — Event System:** event card, weighted spawn, PLAYER_CHOICE, durasi efek (A9)
- [x] **Phase 11 — O2 Tether:** O2 Umbilical Station, Portable O2 Tank, status O2_CUT (A1.2)
- [x] **Phase 12 — UI Lengkap:** HUD stat kapal, tombol End Day, area buka pack, layar game over + skor (A11, A16)
- [x] **Phase 13 — Balancing & Polish:** tuning angka, keputusan open question di A18

---

# BAGIAN D — PROGRESS LOG

- **Phase 0 selesai** — kartu prototype bisa click (signal `clicked`), drag, dan stack ke pile; klik pile untuk pop kartu. Main scene = `main.tscn`, verifikasi headless bersih (Godot 4.7.1 Steam di `D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`). Satu bug sempat muncul (`:=` infer Variant di stack.gd) — sudah diperbaiki.
- **Phase 1 selesai** — Fondasi data lengkap: enum global (`Enums`), `CardData` + 8 subclass, `CraftRecipe`, `SectorData`, `PackDefinition`, autoload `GameState`/`CardDB`/`RecipeDB`, 83 file `.tres` (59 kartu, 14 resep, 5 sektor, 5 pack). Validasi `tests/data_check.gd` lolos: `kartu: 59 | resep: 14 | sektor: 5 | pack: 5` → `DATA CHECK: OK`; run normal headless bersih.
- Keputusan teknis Phase 1: sub-resource bertipe script class (`ItemRequirement`, `ProductionRule`, `EventChoice`) **diganti Dictionary** di `.tres` karena runtime headless tidak mendaftarkan script class ke ClassDB (`Cannot get class 'ItemRequirement'`) — Dictionary selalu bisa di-parse di mode apa pun. File script pendukung (item_requirement.gd, production_rule.gd, event_choice.gd) dihapus; akses data via key dict (`req["item_id"]`, `prod["input_item_id"]`, dst).
- Catatan Phase 1: file `.tres` harus tanpa UTF-8 BOM (PowerShell `Set-Content -Encoding UTF8` menambahkan BOM → `Parse Error: Expected '['`); `role` unit diperbaiki dari off-by-one (astronaut=0, engineer=1, scientist=2, pilot=3, robot_drone=4), validasi role sekarang ada di data_check.gd.
- **Phase 2 selesai** — Board 1 scene 2 zona: `scripts/ui/board.gd` (klas `Board`, zona `SHIP_INTERIOR` kiri 45% / `OPEN_SPACE` kanan 55% + garis airlock, `validate_drop()` per kategori, spawn test dari CardDB, label debug data). `scenes/card.gd|card.tscn` di-refactor: render dari `CardData` (panel + warna placeholder per kategori + nama + label ×N + label kategori), item stacking otomatis (drop item sejenis → merge sampai `stack_max`, sisa pecah jadi kartu baru), drop invalid → revert + flash merah. Aturan drop: BUILDING & PACKAGE hanya Zona Kapal, NODE hanya Zona Angkasa, UNIT/ITEM/TOOL bebas. NODE & EVENT tidak bisa di-drag. `scripts/main.gd` dihapus (diganti board.gd). Verifikasi headless bersih.
- **Phase 3 selesai** — Combine Engine (A13): `scripts/systems/recipe_resolver.gd` (klas `RecipeResolver`, static): `find_recipe()` cek 2 arah dengan kuantitas stack (input ≤2 jenis; resep 1-input = drag material ke atas Unit, mis. Scrap ×3 ke Engineer → Mining Drill), `check_blocked()` (building prasyarat harus ada di board, unit role harus ada), `execute()` (konsumsi input dari stack, spawn output di titik drop). `board.gd`: `_on_card_dropped` (cari kartu target di titik drop → resolve → toast hijau "+ Output" / merah "Butuh X"), `has_building()`, `has_unit_role()`, `spawn_card_at()`. Resep produksi building (`duration_days > 0`) sengaja di-skip manual combine (diproses Phase 6/7). Test otomatis `tests/combine_check.tscn|gd`: 12 kasus pencocokan + 3 alur eksekusi/blokir → `COMBINE CHECK: OK`. Test board Phase 3 berisi material semua resep manual.
- **Phase 4 selesai** — Node & Gather (A3): drag Unit ke Node → `assign_to_node()` (Unit menempel di sisi kanan Node, label "WORKING"), timer gather real-time di `board._tick_gather()` — `effective_interval = gather_interval_sec / efficiency` (efficiency dari `role_efficiency_map` node id, default 1.0). Tiap harvest: `_spawn_nearby()` output di slot kosong terdekat (ring 8 posisi, fallback acak), secondary output (Alien Ruins 50/50) via `secondary_chance`. Node limited (`is_limited`): durability runtime di card (bukan resource bersama — `node_durability_left`, tampil "DUR X"), habis → node hilang, unit balik IDLE. Tool requirement (Gas Cloud butuh Cutting Laser): `has_tool()` cek tool card di board (v1 — sistem equip formal di Phase 5). Drop unit ke tempat kosong → unassign. Test `tests/gather_check.tscn|gd`: 6 alur → `GATHER CHECK: OK`; semua validasi lain tetap OK.
- **FIX TEST PALSU (penting):** `combine_check.gd` & `gather_check.gd` memanggil fungsi alur (yang berisi `await`) TANPA `await` di `_ready` → `_ready` langsung lanjut ke `print OK` + `quit(0)` SEBELUM alur selesai → "OK" selama ini PALSU. Diperbaiki: `await _run_combine_flow_tests()` / `await _run_gather_tests()`; flow combine kini mencari kartu via `board.get_children()` (bukan group — kartu `_make_card` di (0,0) mengganggu `_card_at`); asersi scrap flow A dikoreksi 8-2=6. Setelah fix, gather menemukan bug nyata: harvest gagal karena delta frame headless terlalu kecil untuk `interval - 0.01` → timer sekarang di-set `interval + 0.1`. **Semua test sekarang benar-benar menjalankan alurnya.**
- **Phase 5-13 selesai (satu paket):** 
  - **A4 unit state machine:** `unit_state` IDLE/WORKING/TRAVELING/DEAD di `card.gd`, status di label kartu; kematian → kartu hilang.
  - **A5/A6 tool equip:** drag Tool → Unit = equip (kartu tool dikonsumsi, tampil "EQ: ..."). Tool requirement node (Cutting Laser) sekarang cek equip unit (bukan board). Consumable (Repair Kit → Hull +20, dipakai drag ke Unit). Mining Drill → gather Asteroid Field ×2 (efficiency × effect_value). Portable O2 Tank → `tank_days_left`.
  - **A7 building:** drop kartu building = bayar `build_cost` dari item di board (konsumsi otomatis, toast "Butuh: ..." jika kurang) → `is_built` (tidak bisa di-drag lagi). Drag Unit → building = WORKING (slot `max_unit_slots`). Produksi harian: End Day, butuh unit + power + bahan.
  - **A14/A15 Day Cycle:** autoload `DayCycle.end_day()` 11 langkah: produksi → konsumsi food stock (4/unit × multiplier) → replenish O2 canister (25/unit) → stat → power (generated solar + cap 50, auto-shutdown bangunan non-life-support urut power_draw terbesar, nyala ulang jika cukup) → tether/O2_CUT → kematian (O2=0 25%/hari, food 3 hari 1 unit; Med Bay cegah 1/hari) → traveling → event → efek durasi berkurang → game over → skor.
  - **A16 scaling:** consumption ×(1+0.02×day), event severity ×(1+0.015×day), reward ×(1+0.01×day); skor = hari×100 + kredit + paket×50.
  - **A8/A9/A10/A12:** autoload `Packages` (assembly item→package "x/y"→READY, depart unit → TRAVELING, `travel_days = jarak sektor`, Pilot −1 hari, reward di End Day, sektor terkunci rep), `Events` (roll harian P=clamp(0.15+0.01d), pick berbobot `spawn_weight`, DAMAGE_HULL/O2, STEAL_RESOURCE, POWER_DEBUFF durasi, BUFF_LOOT meteorite, PLAYER_CHOICE via kartu event + popup HUD), `Economy` (jual di Trade Post `sell_value × rarity mult`, pack harga progresif +5% per pembelian, buka pack drop table berbobot).
  - **A1.2 tether:** drop unit ke Zona Angkasa butuh slot O2 Umbilical Station (2) atau Portable O2 Tank; label "TETHERED"; End Day: station mati listrik → "O2 CUT!" (25% mati/hari), tank berkurang/hari.
  - **A11 UI:** `scripts/ui/hud.gd` — stat bar (Hari/O2/Food/Hull/Power/Cr/Rep/Skor), tombol End Day, tombol beli 5 pack, popup pilihan event, layar Game Over + skor + tombol Main Lagi.
  - Test baru `tests/gameplay_check.tscn|gd`: 8 alur (repair kit, build cost, jual, produksi End Day, package, tether, event choice, game over) → `GAMEPLAY CHECK: OK`. Semua validasi: `DATA CHECK: OK`, `COMBINE CHECK: OK`, `GATHER CHECK: OK`, `GAMEPLAY CHECK: OK`, run headless 240 frame bersih.
- **Playtest fix (user):** kartu dikecilkan 25% (120×170 → 90×128, font & posisi elemen di-scale); offset assign unit & ring spawn kartu ikut disesuaikan. **Produksi building diubah dari End Day → real-time** (Stacklands-style): `board._tick_production()` — progress bar kini tampil di kartu unit saat WORKING di building produksi (interval = `interval_days` × 10 detik, pause jika bahan kurang / tanpa worker / mati listrik), bahan dikonsumsi + output spawn saat bar penuh. Step produksi dihapus dari `DayCycle.end_day`. Test gameplay alur D disesuaikan; semua validasi tetap OK.
- *(isi log di sini tiap ada perubahan)*

---

# BAGIAN E — OPEN QUESTIONS (dari GDD §18, keputusan ditunda)

- **1 Day real-time timer vs "End Day" manual murni? → KEPUTUSAN: hybrid (sudah diimplementasi).** Gather real-time (timer per unit, progres bar di kartu ala Stacklands); produksi building, konsumsi food/O2, kematian, traveling, event → resolve di End Day.
- **Balancing angka pasti (base_value, interval, cost) → KEPUTUSAN: baseline dipertahankan dulu.** Wajib di-tuning setelah playtest pertama; formula scaling A16 sudah menaikkan kesulitan per hari.
- **Defense Turret / combat system → KEPUTUSAN: placeholder.** Tidak ada combat di v1; event DAMAGE_HULL jadi satu-satunya ancaman hull (plus Repair Kit). Dapat ditambah belakangan.
- **Morale system → KEPUTUSAN: opsional, tidak diimplementasi di v1.** Field `morale` tetap ada di GameState, efeknya belum dipakai.
- **Slot O2 Umbilical Station: shared free-for-all vs assign manual? → KEPUTUSAN: shared free-for-all.** Unit yang masuk Zona Angkasa otomatis mengambil slot kosong; slot penuh → drop ditolak + toast.
- **Tether punya limit jarak visual atau bebas sepanjang board? → KEPUTUSAN: bebas sepanjang board.** Tanpa garis visual di v1 (label status saja); garis Line2D bisa ditambah di polish.
- **Recharge Portable O2 Tank: butuh Power/waktu vs instan? → KEPUTUSAN: v1 konsumsi harian saja.** `tank_duration_days` dikurangi tiap End Day saat unit di angkasa; isi ulang = equipp portable tank baru (belum ada recipe — tambah nanti saat balancing).
- **Zona Kapal: slot cap tetap vs expand otomatis? → KEPUTUSAN: tanpa cap di v1.** Kartu bebas ditumpuk/tersebar di zona kapal.
- **Visual transisi pindah sektor: reset Node lama vs tambah area baru? → KEPUTUSAN: belum ada pindah sektor di v1.** Sektor hanya jadi tujuan paket; unlock via reputation.

---

*Plan.md v3 — di-sync dengan GDD v2 (sumber: Downloads\GDD_Space_Salvage.md). Referensi internal menggunakan penomoran A# (A0–A18).*