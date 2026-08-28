
class TaxonomyConstants {
  // Map<Category, Map<SubCategory, List<TaxonomyItem>>>
  static final Map<String, Map<String, List<TaxonomyItem>>> hierarchy = {
    'Fresh Produce': {
      'Leafy Greens & Cruciferous': [
        TaxonomyItem('Spinach/Kale', 'essential'),
        TaxonomyItem('Lettuce/Salad Greens', 'essential'),
        TaxonomyItem('Broccoli/Cauliflower', 'essential'),
        TaxonomyItem('Cabbage (Red/White/Napa)', 'essential'),
        TaxonomyItem('Brussels Sprouts', 'essential'),
      ],
      'Root Vegetables & Tubers': [
        TaxonomyItem('Potatoes (White/Red)', 'essential'),
        TaxonomyItem('Sweet Potatoes/Yams', 'essential'),
        TaxonomyItem('Carrots', 'essential'),
        TaxonomyItem('Onions (Red/White/Yellow)', 'essential'),
        TaxonomyItem('Garlic/Shallots', 'essential'),
        TaxonomyItem('Beets/Radishes', 'essential'),
        TaxonomyItem('Ginger/Turmeric Root', 'essential'),
      ],
      'Fruit Vegetables': [
        TaxonomyItem('Tomatoes', 'essential'),
        TaxonomyItem('Bell Peppers (Capsicum)', 'essential'),
        TaxonomyItem('Cucumbers', 'essential'),
        TaxonomyItem('Zucchini/Eggplant', 'essential'),
        TaxonomyItem('Pumpkins/Squash', 'essential'),
        TaxonomyItem('Avocados', 'discretional'),
        TaxonomyItem('Chili Peppers (Fresh)', 'discretional'),
      ],
      'Fruits': [
        TaxonomyItem('Bananas', 'essential'),
        TaxonomyItem('Apples/Pears', 'essential'),
        TaxonomyItem('Citrus (Oranges/Lemons/Limes)', 'essential'),
        TaxonomyItem('Grapes', 'discretional'),
        TaxonomyItem('Berries (Strawberries/Blueberries)', 'discretional'),
        TaxonomyItem('Stone Fruit', 'discretional'),
        TaxonomyItem('Tropical (Mango/Pineapple)', 'discretional'),
        TaxonomyItem('Melons', 'discretional'),
      ],
      'Fresh Herbs & Fungi': [
        TaxonomyItem('Mushrooms (White/Cremini)', 'essential'),
        TaxonomyItem('Specialty Mushrooms', 'discretional'),
        TaxonomyItem('Fresh Parsley/Cilantro', 'discretional'),
        TaxonomyItem('Fresh Basil/Mint/Rosemary', 'discretional'),
      ],
    },
    'Proteins & Dairy': {
      'Butcher Counter': [
        TaxonomyItem('Chicken (Whole/Breast/Thighs)', 'essential'),
        TaxonomyItem('Ground Beef/Pork/Turkey', 'essential'),
        TaxonomyItem('Pork Chops/Loin', 'essential'),
        TaxonomyItem('Beef Steaks', 'discretional'),
        TaxonomyItem('Lamb/Veal', 'discretional'),
        TaxonomyItem('Sausages (Fresh)', 'discretional'),
        TaxonomyItem('Bacon/Pancetta', 'junk'),
        TaxonomyItem('Hot Dogs/Frankfurters', 'junk'),
      ],
      'Seafood': [
        TaxonomyItem('White Fish (Cod/Tilapia)', 'essential'),
        TaxonomyItem('Oily Fish (Salmon/Trout)', 'essential'),
        TaxonomyItem('Shrimp/Prawns', 'discretional'),
        TaxonomyItem('Shellfish', 'discretional'),
        TaxonomyItem('Smoked Salmon', 'discretional'),
        TaxonomyItem('Lobster/Crab/Caviar', 'junk'),
      ],
      'Plant-Based Protein': [
        TaxonomyItem('Tofu (Firm/Silken)', 'essential'),
        TaxonomyItem('Tempeh/Seitan', 'essential'),
        TaxonomyItem('Plant-Based Meat', 'discretional'),
      ],
      'Dairy & Alternatives': [
        TaxonomyItem('Milk (Whole/Skim)', 'essential'),
        TaxonomyItem('Plant Milk', 'essential'),
        TaxonomyItem('Eggs (Standard)', 'essential'),
        TaxonomyItem('Butter', 'essential'),
        TaxonomyItem('Yogurt (Plain/Greek)', 'essential'),
        TaxonomyItem('Yogurt (Fruit/Sugared)', 'junk'),
        TaxonomyItem('Cheese (Cheddar/Mozzarella)', 'essential'),
        TaxonomyItem('Cheese (Fancy)', 'discretional'),
        TaxonomyItem('Cream/Sour Cream', 'discretional'),
        TaxonomyItem('Whipped Cream', 'junk'),
      ],
    },
    'Pantry & Bakery': {
      'Bakery': [
        TaxonomyItem('Sliced Bread', 'essential'),
        TaxonomyItem('Artisan Bread', 'discretional'),
        TaxonomyItem('Bagels/Muffins', 'discretional'),
        TaxonomyItem('Tortillas/Wraps', 'essential'),
        TaxonomyItem('Croissants/Danishes', 'junk'),
        TaxonomyItem('Donuts/Muffins', 'junk'),
        TaxonomyItem('Cakes/Cupcakes', 'junk'),
      ],
      'Grains & Pasta': [
        TaxonomyItem('Rice', 'essential'),
        TaxonomyItem('Pasta', 'essential'),
        TaxonomyItem('Specialty Pasta', 'discretional'),
        TaxonomyItem('Quinoa/Couscous', 'discretional'),
        TaxonomyItem('Instant Noodles', 'junk'),
      ],
      'Baking Ingredients': [
        TaxonomyItem('Flour', 'essential'),
        TaxonomyItem('Sugar', 'essential'),
        TaxonomyItem('Baking Powder/Soda', 'essential'),
        TaxonomyItem('Yeast', 'essential'),
        TaxonomyItem('Vanilla Extract', 'discretional'),
        TaxonomyItem('Choco Chips/Sprinkles', 'junk'),
        TaxonomyItem('Cake Mixes', 'junk'),
      ],
      'Condiments': [
        TaxonomyItem('Oil (Olive/Veg)', 'essential'),
        TaxonomyItem('Vinegar', 'essential'),
        TaxonomyItem('Soy Sauce', 'essential'),
        TaxonomyItem('Tomato Paste', 'essential'),
        TaxonomyItem('Coconut Milk', 'discretional'),
        TaxonomyItem('Hot Sauce', 'discretional'),
        TaxonomyItem('Mayo/Ketchup', 'discretional'),
        TaxonomyItem('BBQ/Salad Dressing', 'junk'),
        TaxonomyItem('Nutella', 'junk'),
        TaxonomyItem('Jam/PB', 'discretional'),
      ],
    },
    'Frozen Foods': {
      'Frozen Ingredients': [
        TaxonomyItem('Frozen Veg', 'essential'),
        TaxonomyItem('Frozen Fruit', 'essential'),
        TaxonomyItem('Frozen Meat/Fish', 'essential'),
      ],
      'Frozen Prepared': [
        TaxonomyItem('Pizza', 'junk'),
        TaxonomyItem('Fries/Rings', 'junk'),
        TaxonomyItem('Nuggets/Fish Sticks', 'junk'),
        TaxonomyItem('Ice Cream', 'junk'),
        TaxonomyItem('TV Dinners', 'junk'),
      ],
    },
    'Snacks & Drinks': {
      'Savory Snacks': [
        TaxonomyItem('Chips/Crisps', 'junk'),
        TaxonomyItem('Nachos', 'junk'),
        TaxonomyItem('Popcorn', 'junk'),
        TaxonomyItem('Crackers', 'discretional'),
        TaxonomyItem('Nuts', 'discretional'),
        TaxonomyItem('Beef Jerky', 'discretional'),
      ],
      'Sweet Snacks': [
        TaxonomyItem('Chocolate', 'junk'),
        TaxonomyItem('Candy/Gummies', 'junk'),
        TaxonomyItem('Cookies', 'junk'),
        TaxonomyItem('Protein Bars', 'discretional'),
        TaxonomyItem('Dried Fruit', 'discretional'),
      ],
      'Beverages': [
        TaxonomyItem('Water', 'essential'),
        TaxonomyItem('Coffee', 'discretional'),
        TaxonomyItem('Tea', 'discretional'),
        TaxonomyItem('Soda', 'junk'),
        TaxonomyItem('Energy Drinks', 'junk'),
        TaxonomyItem('Juice', 'junk'),
        TaxonomyItem('Iced Tea', 'junk'),
      ],
      'Alcohol': [
        TaxonomyItem('Beer', 'junk'),
        TaxonomyItem('Wine', 'junk'),
        TaxonomyItem('Spirits', 'junk'),
        TaxonomyItem('Mixers', 'junk'),
      ],
    },
    'Household & Living': {
      'Kitchen & Cleaning': [
        TaxonomyItem('Dish Soap', 'essential'),
        TaxonomyItem('Sponges', 'essential'),
        TaxonomyItem('Laundry Detergent', 'essential'),
        TaxonomyItem('Fabric Softener', 'discretional'),
        TaxonomyItem('Cleaner', 'essential'),
        TaxonomyItem('Trash Bags', 'essential'),
        TaxonomyItem('Foil/Wrap', 'discretional'),
        TaxonomyItem('Paper Towels', 'discretional'),
        TaxonomyItem('Toilet Paper', 'essential'),
      ],
      'Maintenance': [
        TaxonomyItem('Batteries', 'essential'),
        TaxonomyItem('Light Bulbs', 'essential'),
        TaxonomyItem('Matches', 'essential'),
        TaxonomyItem('Pest Control', 'essential'),
      ],
      'Office': [
        TaxonomyItem('Paper', 'discretional'),
        TaxonomyItem('Pens', 'discretional'),
        TaxonomyItem('Notebooks', 'discretional'),
        TaxonomyItem('Tape/Glue', 'discretional'),
      ],
    },
    'Personal Care': {
      'Bathroom Basics': [
        TaxonomyItem('Toothpaste/Floss', 'essential'),
        TaxonomyItem('Toothbrushes', 'essential'),
        TaxonomyItem('Shampoo/Conditioner', 'essential'),
        TaxonomyItem('Body Wash/Soap', 'essential'),
        TaxonomyItem('Hand Soap', 'essential'),
        TaxonomyItem('Deodorant', 'essential'),
        TaxonomyItem('Razors', 'essential'),
      ],
      'Skin & Beauty': [
        TaxonomyItem('Face Care/Sunscreen', 'essential'),
        TaxonomyItem('Body Lotion', 'discretional'),
        TaxonomyItem('Makeup', 'discretional'),
        TaxonomyItem('Nail Polish', 'junk'),
        TaxonomyItem('Perfume', 'junk'),
      ],
      'Health': [
        TaxonomyItem('Pain Relief', 'essential'),
        TaxonomyItem('Cold/Flu Meds', 'essential'),
        TaxonomyItem('Vitamins', 'discretional'),
        TaxonomyItem('First Aid', 'essential'),
        TaxonomyItem('Feminine Hygiene', 'essential'),
        TaxonomyItem('Contraceptives', 'essential'),
      ],
    },
    'Miscellaneous': {
      'Baby': [
        TaxonomyItem('Diapers', 'essential'),
        TaxonomyItem('Wipes', 'essential'),
        TaxonomyItem('Formula', 'essential'),
        TaxonomyItem('Baby Food', 'discretional'),
      ],
      'Pets': [
        TaxonomyItem('Pet Food (Dry/Wet)', 'essential'),
        TaxonomyItem('Cat Litter', 'essential'),
        TaxonomyItem('Treats/Toys', 'discretional'),
      ],
      'Automotive': [
        TaxonomyItem('Windshield Fluid', 'essential'),
        TaxonomyItem('Motor Oil', 'essential'),
        TaxonomyItem('Air Freshener', 'junk'),
      ],
      'Vices': [
        TaxonomyItem('Tobacco', 'junk'),
        TaxonomyItem('Vape', 'junk'),
        TaxonomyItem('Lottery', 'junk'),
      ],
    },
  };

  static const Map<String, String> necessityLabels = {
    'essential': 'Essential',
    'discretional': 'Discretional',
    'junk': 'Junk',
    'unknown': '?',
  };
}

class TaxonomyItem {
  final String name;
  final String defaultNecessity;
  const TaxonomyItem(this.name, this.defaultNecessity);
}
