import '../models/menu_item.dart';
import '../utils/currency.dart';

// Shared customization options.
const _dips = [
  AddOn(id: 'mint_mayo', name: 'Mint Mayo Dip', price: Money.rupees(30)),
  AddOn(
    id: 'extra_onion',
    name: 'Lemon & Onion Rings',
    price: Money.rupees(15),
  ),
];

const _starterPortions = [
  PortionOption(id: 'half', label: 'Half', detail: '6 pieces'),
  PortionOption(
    id: 'full',
    label: 'Full',
    detail: '12 pieces',
    extraPrice: Money.rupees(140),
  ),
];

const _curryAddOns = [
  AddOn(id: 'butter', name: 'Extra Butter', price: Money.rupees(25)),
  AddOn(id: 'cream', name: 'Fresh Cream', price: Money.rupees(30)),
  AddOn(id: 'naan', name: 'Butter Naan', price: Money.rupees(45)),
];

const _biryaniAddOns = [
  AddOn(id: 'raita', name: 'Boondi Raita', price: Money.rupees(40)),
  AddOn(id: 'salan', name: 'Mirchi ka Salan', price: Money.rupees(50)),
  AddOn(id: 'egg', name: 'Boiled Egg', price: Money.rupees(20)),
];

const _drinkSizes = [
  PortionOption(id: 'regular', label: 'Regular', detail: '300 ml'),
  PortionOption(
    id: 'large',
    label: 'Large',
    detail: '500 ml',
    extraPrice: Money.rupees(40),
  ),
];

const _dessertAddOns = [
  AddOn(id: 'ice_cream', name: 'Vanilla Ice Cream', price: Money.rupees(50)),
];

/// Static menu for the offline demo restaurant.
const demoMenuItems = <MenuItem>[
  // Starters
  MenuItem(
    id: 'chicken_65',
    name: 'Chicken 65',
    category: MenuCategory.starters,
    shortDescription: 'Spicy and crispy chicken bites',
    description:
        'Spicy and crispy chicken bites with authentic South Indian flavour, '
        'tempered with curry leaves and green chillies, served with onions and lemon.',
    price: Money.rupees(180),
    image: 'assets/images/chicken_65.jpg',
    isVeg: false,
    rating: 4.5,
    reviewCount: 120,
    isPopular: true,
    isFeatured: true,
    hasSpiceLevel: true,
    portions: _starterPortions,
    addOns: _dips,
    prepMinutes: 15,
  ),
  MenuItem(
    id: 'paneer_tikka',
    name: 'Paneer Tikka',
    category: MenuCategory.starters,
    shortDescription: 'Grilled paneer with spices',
    description:
        'Cottage cheese cubes marinated in hung curd and tandoori spices, '
        'chargrilled with peppers and onions and finished with chaat masala.',
    price: Money.rupees(200),
    image: 'assets/images/paneer_tikka.jpg',
    isVeg: true,
    rating: 4.6,
    reviewCount: 98,
    isPopular: true,
    hasSpiceLevel: true,
    portions: _starterPortions,
    addOns: _dips,
    prepMinutes: 18,
  ),
  MenuItem(
    id: 'french_fries',
    name: 'French Fries',
    category: MenuCategory.starters,
    shortDescription: 'Crispy golden fries',
    description:
        'Golden, crispy potato fries tossed in sea salt and served with tomato ketchup. '
        'Add peri-peri seasoning for a little heat.',
    price: Money.rupees(120),
    image: 'assets/images/french_fries.jpg',
    isVeg: true,
    rating: 4.2,
    reviewCount: 76,
    addOns: [
      AddOn(
        id: 'peri_peri',
        name: 'Peri-Peri Seasoning',
        price: Money.rupees(20),
      ),
      AddOn(id: 'cheese_dip', name: 'Cheese Dip', price: Money.rupees(35)),
    ],
    prepMinutes: 10,
  ),
  MenuItem(
    id: 'chilli_chicken',
    name: 'Chilli Chicken',
    category: MenuCategory.starters,
    shortDescription: 'Indo-Chinese style',
    description:
        'Crispy chicken tossed in a glossy soy-chilli sauce with spring onions, '
        'capsicum and fresh red chillies. A Kolkata-style Indo-Chinese favourite.',
    price: Money.rupees(190),
    image: 'assets/images/chilli_chicken.jpg',
    isVeg: false,
    rating: 4.4,
    reviewCount: 88,
    hasSpiceLevel: true,
    portions: _starterPortions,
    prepMinutes: 15,
  ),
  MenuItem(
    id: 'spring_roll',
    name: 'Spring Roll',
    category: MenuCategory.starters,
    shortDescription: 'Crispy vegetable rolls',
    description:
        'Thin, flaky rolls filled with stir-fried cabbage, carrots and glass noodles, '
        'fried golden and served with sweet chilli sauce.',
    price: Money.rupees(140),
    image: 'assets/images/spring_roll.jpg',
    isVeg: true,
    rating: 4.1,
    reviewCount: 54,
    addOns: [
      AddOn(id: 'schezwan', name: 'Schezwan Dip', price: Money.rupees(20)),
    ],
    prepMinutes: 12,
  ),
  MenuItem(
    id: 'veg_manchurian',
    name: 'Veg Manchurian',
    category: MenuCategory.starters,
    shortDescription: 'Crispy cauliflower in Manchurian sauce',
    description:
        'Crisp cauliflower florets tossed in a tangy garlic, ginger and soy '
        'Manchurian sauce, garnished with spring onions.',
    price: Money.rupees(150),
    image: 'assets/images/veg_manchurian.jpg',
    isVeg: true,
    rating: 4.3,
    reviewCount: 102,
    isPopular: true,
    hasSpiceLevel: true,
    prepMinutes: 14,
  ),
  MenuItem(
    id: 'samosa',
    name: 'Punjabi Samosa',
    category: MenuCategory.starters,
    shortDescription: 'Two flaky pastries, spiced potato',
    description:
        'Two hand-folded pastries stuffed with spiced potato and green peas, '
        'served with tamarind and mint chutneys.',
    price: Money.rupees(60),
    image: 'assets/images/samosa.jpg',
    isVeg: true,
    rating: 4.4,
    reviewCount: 143,
    prepMinutes: 8,
  ),
  MenuItem(
    id: 'tandoori_chicken',
    name: 'Tandoori Chicken',
    category: MenuCategory.starters,
    shortDescription: 'Clay-oven roasted, smoky',
    description:
        'Bone-in chicken marinated overnight in yoghurt, Kashmiri chilli and '
        'garam masala, roasted in the tandoor until smoky and tender.',
    price: Money.rupees(320),
    image: 'assets/images/tandoori_chicken.jpg',
    isVeg: false,
    rating: 4.7,
    reviewCount: 131,
    isChefSpecial: true,
    hasSpiceLevel: true,
    portions: [
      PortionOption(id: 'half', label: 'Half', detail: '2 pieces'),
      PortionOption(
        id: 'full',
        label: 'Full',
        detail: '4 pieces',
        extraPrice: Money.rupees(240),
      ),
    ],
    addOns: _dips,
    prepMinutes: 25,
  ),

  // Main course
  MenuItem(
    id: 'chicken_biryani',
    name: 'Chicken Biryani',
    category: MenuCategory.mainCourse,
    shortDescription: 'Hyderabadi dum biryani',
    description:
        'Long-grain basmati layered with saffron and tender chicken, '
        'slow-cooked on dum the Hyderabadi way. Served with raita.',
    price: Money.rupees(260),
    image: 'assets/images/chicken_biryani.jpg',
    isVeg: false,
    rating: 4.8,
    reviewCount: 214,
    isPopular: true,
    isChefSpecial: true,
    isFeatured: true,
    hasSpiceLevel: true,
    addOns: _biryaniAddOns,
    prepMinutes: 22,
  ),
  MenuItem(
    id: 'veg_biryani',
    name: 'Veg Biryani',
    category: MenuCategory.mainCourse,
    shortDescription: 'Fragrant rice, garden vegetables',
    description:
        'Aromatic basmati rice cooked with paneer, carrots, peas and cauliflower '
        'in whole spices. Served with pomegranate raita.',
    price: Money.rupees(200),
    image: 'assets/images/veg_biryani.jpg',
    isVeg: true,
    rating: 4.3,
    reviewCount: 87,
    hasSpiceLevel: true,
    addOns: [
      AddOn(id: 'raita', name: 'Boondi Raita', price: Money.rupees(40)),
      AddOn(id: 'salan', name: 'Mirchi ka Salan', price: Money.rupees(50)),
    ],
    prepMinutes: 20,
  ),
  MenuItem(
    id: 'butter_chicken',
    name: 'Butter Chicken',
    category: MenuCategory.mainCourse,
    shortDescription: 'Creamy tomato makhani gravy',
    description:
        'Tandoori chicken simmered in a velvety tomato, butter and cashew gravy '
        'with a hint of fenugreek. Best with butter naan.',
    price: Money.rupees(280),
    image: 'assets/images/butter_chicken.jpg',
    isVeg: false,
    rating: 4.7,
    reviewCount: 189,
    isPopular: true,
    isChefSpecial: true,
    hasSpiceLevel: true,
    defaultSpice: SpiceLevel.mild,
    addOns: _curryAddOns,
    prepMinutes: 20,
  ),
  MenuItem(
    id: 'paneer_butter_masala',
    name: 'Paneer Butter Masala',
    category: MenuCategory.mainCourse,
    shortDescription: 'Soft paneer, rich makhani gravy',
    description:
        'Soft paneer cubes in a rich, mildly sweet tomato and butter gravy, '
        'finished with fresh cream and kasuri methi.',
    price: Money.rupees(230),
    image: 'assets/images/paneer_butter_masala.jpg',
    isVeg: true,
    rating: 4.5,
    reviewCount: 142,
    isChefSpecial: true,
    hasSpiceLevel: true,
    defaultSpice: SpiceLevel.mild,
    addOns: _curryAddOns,
    prepMinutes: 18,
  ),
  MenuItem(
    id: 'masala_dosa',
    name: 'Masala Dosa',
    category: MenuCategory.mainCourse,
    shortDescription: 'Crisp crepe, potato masala',
    description:
        'A crisp, golden rice-and-lentil crepe filled with spiced potato masala, '
        'served with coconut chutney and sambar.',
    price: Money.rupees(100),
    image: 'assets/images/masala_dosa.jpg',
    isVeg: true,
    rating: 4.6,
    reviewCount: 176,
    isPopular: true,
    addOns: [
      AddOn(id: 'ghee', name: 'Ghee Roast', price: Money.rupees(30)),
      AddOn(id: 'cheese', name: 'Cheese', price: Money.rupees(40)),
    ],
    prepMinutes: 12,
  ),
  MenuItem(
    id: 'butter_naan',
    name: 'Butter Naan',
    category: MenuCategory.mainCourse,
    shortDescription: 'Tandoor bread, brushed with butter',
    description:
        'Soft, pillowy leavened bread baked in the tandoor and brushed with butter. '
        'Pick garlic for an extra punch.',
    price: Money.rupees(45),
    image: 'assets/images/butter_naan.jpg',
    isVeg: true,
    rating: 4.4,
    reviewCount: 95,
    addOns: [
      AddOn(id: 'garlic', name: 'Garlic & Coriander', price: Money.rupees(15)),
    ],
    prepMinutes: 8,
  ),
  MenuItem(
    id: 'dal_makhani',
    name: 'Dal Makhani',
    category: MenuCategory.mainCourse,
    shortDescription: 'Slow-cooked black lentils',
    description:
        'Whole black lentils and kidney beans slow-cooked overnight with butter '
        'and cream. Served with steamed rice.',
    price: Money.rupees(210),
    image: 'assets/images/dal_makhani.jpg',
    isVeg: true,
    rating: 4.5,
    reviewCount: 118,
    isChefSpecial: true,
    addOns: [
      AddOn(id: 'butter', name: 'Extra Butter', price: Money.rupees(25)),
      AddOn(
        id: 'jeera_rice',
        name: 'Jeera Rice (upgrade)',
        price: Money.rupees(40),
      ),
    ],
    prepMinutes: 15,
  ),

  // Beverages
  MenuItem(
    id: 'fresh_lime_soda',
    name: 'Fresh Lime Soda',
    category: MenuCategory.beverages,
    shortDescription: 'Sweet, salted or mixed',
    description:
        'Freshly squeezed lime topped with chilled soda and a sprig of mint. '
        'The perfect palate cleanser between spicy bites.',
    price: Money.rupees(80),
    image: 'assets/images/fresh_lime_soda.jpg',
    isVeg: true,
    rating: 4.3,
    reviewCount: 67,
    portions: _drinkSizes,
    prepMinutes: 5,
  ),
  MenuItem(
    id: 'cold_coffee',
    name: 'Cold Coffee',
    category: MenuCategory.beverages,
    shortDescription: 'Frothy, chilled and creamy',
    description:
        'Chilled coffee whipped with milk until frothy. Add a scoop of '
        'vanilla ice cream to make it extra indulgent.',
    price: Money.rupees(120),
    image: 'assets/images/cold_coffee.jpg',
    isVeg: true,
    rating: 4.5,
    reviewCount: 109,
    isPopular: true,
    portions: _drinkSizes,
    addOns: _dessertAddOns,
    prepMinutes: 5,
  ),
  MenuItem(
    id: 'lassi',
    name: 'Classic Lassi',
    category: MenuCategory.beverages,
    shortDescription: 'Churned yoghurt, cardamom',
    description:
        'Thick, chilled yoghurt churned with a touch of sugar and cardamom, '
        'topped with a pinch of nutmeg.',
    price: Money.rupees(90),
    image: 'assets/images/lassi.jpg',
    isVeg: true,
    rating: 4.4,
    reviewCount: 72,
    portions: _drinkSizes,
    prepMinutes: 5,
  ),

  // Desserts
  MenuItem(
    id: 'gulab_jamun',
    name: 'Gulab Jamun',
    category: MenuCategory.desserts,
    shortDescription: 'Warm, syrup-soaked dumplings',
    description:
        'Two soft milk-solid dumplings fried golden and soaked in warm '
        'rose and cardamom syrup.',
    price: Money.rupees(90),
    image: 'assets/images/gulab_jamun.jpg',
    isVeg: true,
    rating: 4.7,
    reviewCount: 156,
    isPopular: true,
    isFeatured: true,
    addOns: _dessertAddOns,
    prepMinutes: 5,
  ),
  MenuItem(
    id: 'rasmalai',
    name: 'Rasmalai',
    category: MenuCategory.desserts,
    shortDescription: 'Chenna discs in saffron milk',
    description:
        'Delicate cottage cheese discs soaked in chilled saffron milk, '
        'garnished with pistachios and almonds.',
    price: Money.rupees(120),
    image: 'assets/images/rasmalai.jpg',
    isVeg: true,
    rating: 4.6,
    reviewCount: 83,
    isChefSpecial: true,
    prepMinutes: 5,
  ),
  MenuItem(
    id: 'affogato',
    name: 'Vanilla Affogato',
    category: MenuCategory.desserts,
    shortDescription: 'Ice cream drowned in espresso',
    description:
        'A scoop of vanilla bean ice cream drowned in a hot shot of espresso. '
        'Simple, bittersweet and impossible to resist.',
    price: Money.rupees(150),
    image: 'assets/images/affogato.jpg',
    isVeg: true,
    rating: 4.4,
    reviewCount: 41,
    prepMinutes: 5,
  ),
];
