import Foundation

// MARK: - Agent Names with SF Symbols

let agentNamesWithIcons: [(name: String, icon: String)] = [

    // James Bond

    ("Agent 007", "target"), ("Le Chiffre", "suit.diamond.fill"), ("Blofeld", "cat.fill"), ("Moneypenny", "pencil"),
    ("Goldfinger", "dollarsign.circle.fill"), ("Oddjob", "hat.widebrim.fill"), ("Vesper Lynd", "heart.fill"), ("Jaws", "bolt.fill"),

    // The Matrix

    ("Agent Smith", "person.fill"), ("Neo", "pills.fill"), ("Morpheus", "moon.fill"), ("Trinity", "heart.fill"),
    ("The Oracle", "eye.fill"), ("Cypher", "key.fill"), ("The Architect", "building.2.fill"),

    // Terminator

    ("T-800", "figure.stand"), ("T-1000", "drop.fill"), ("Skynet", "network"), ("John Connor", "star.fill"), ("Sarah Connor", "bolt.fill"),

    // AI & Robots

    ("HAL 9000", "circle.fill"), ("JARVIS", "desktopcomputer"), ("FRIDAY", "diamond.fill"), ("Cortana", "waveform"), ("GLaDOS", "cube.fill"),
    ("Ultron", "bolt.circle.fill"), ("WALL-E", "gearshape.fill"), ("Samantha", "headphones"), ("Mr. Robot", "terminal.fill"),

    // Star Wars

    ("Anakin", "flame.fill"), ("R2-D2", "antenna.radiowaves.left.and.right"), ("C-3PO", "figure.wave"),

    // Spy & Espionage

    ("Jason Bourne", "brain.head.profile"), ("Ethan Hunt", "theatermasks.fill"), ("Jack Bauer", "clock.fill"), ("Jack Ryan", "flag.fill"),
    ("Agent K", "sunglasses.fill"), ("Agent J", "star.fill"), ("Sterling Archer", "scope"), ("Austin Powers", "sun.max.fill"),
    ("Agent Coulson", "shield.fill"), ("Agent Carter", "person.crop.circle.fill"), ("Maxwell Smart", "shoe.fill"), ("Sydney Bristow", "figure.wave"),
    ("Kingsman", "umbrella.fill"),

    // Blade Runner

    ("Roy Batty", "bird.fill"), ("Rachael", "leaf.fill"), ("Deckard", "cloud.rain.fill"),

    // Action Heroes

    ("John Wick", "dog.fill"), ("Indiana Jones", "lasso"), ("Ripley", "cat.fill"), ("RoboCop", "figure.stand"),
    ("Mad Max", "car.fill"), ("Furiosa", "gearshape.fill"), ("The Bride", "scissors"), ("Snake Plissken", "eye.slash.fill"),

    // Marvel

    ("Tony Stark", "bolt.fill"), ("Nick Fury", "eye.slash.fill"), ("Black Widow", "ant.fill"),

    // Hackers

    ("Zero Cool", "snowflake.circle.fill"), ("Crash Override", "exclamationmark.triangle.fill"), ("Acid Burn", "flame.circle.fill"),
    ("Elliot Alderson", "terminal.fill"),

    // Classic Detectives

    ("Sherlock", "magnifyingglass"), ("Columbo", "eyeglasses"),

    // Metal Gear

    ("Solid Snake", "shippingbox.fill"), ("Big Boss", "eye.circle.fill"),

    // Anime

    ("Spike Spiegel", "airplane"), ("Motoko Kusanagi", "brain"),

    // The Office

    ("Dwight Schrute", "leaf.fill"),

    // Tron

    ("Tron", "circle.grid.cross.fill"), ("CLU", "square.grid.3x3.fill"),

    // WarGames

    ("David Lightman", "desktopcomputer"), ("WOPR", "exclamationmark.triangle.fill"),

    // Westworld

    ("Dolores", "brain"), ("Bernard", "eye.fill"), ("Maeve", "sparkles"),

    // Person of Interest

    ("Finch", "bird.fill"), ("The Machine", "eye.circle.fill"), ("Root", "terminal.fill"),

    // Ex Machina

    ("Ava", "figure.stand"), ("Nathan Bateman", "lock.fill"),

    // Misc

    ("Lara Croft", "scope"), ("Patrick Kane", "sportscourt.fill")
]

let agentNames: [String] = agentNamesWithIcons.map { $0.name }

func iconForAgent(_ name: String) -> String {
    return agentNamesWithIcons.first { $0.name == name }?.icon ?? "cpu.fill"
}
