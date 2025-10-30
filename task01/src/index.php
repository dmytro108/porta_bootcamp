<?php
// Database configuration
$host = $_ENV['DB_HOST'];
$dbname = $_ENV['DB_NAME'];
$username = $_ENV['DB_USER'];
$password = $_ENV['DB_PASSWORD'];

// Create connection
try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8mb4", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Connection failed: " . $e->getMessage());
}

// Handle form submission for adding new rating
if (($_POST['action'] ?? '') === 'add_rating') {
    if (isset($_POST['reviewer_id'], $_POST['movie_id'], $_POST['stars'])) {
        $reviewer_id = (int)$_POST['reviewer_id'];
        $movie_id = (int)$_POST['movie_id'];
        $stars = (int)$_POST['stars'];
        $ratingDate = !empty($_POST['rating_date']) ? $_POST['rating_date'] : null;
        
        // Validate stars range
        if ($stars < 1 || $stars > 5) {
            $error_message = "Stars must be between 1 and 5.";
        } else {
            try {
                // Check if movie exists
                $check_movie = $pdo->prepare("SELECT COUNT(*) FROM Movie WHERE mID = ?");
                $check_movie->execute([$movie_id]);
                if ($check_movie->fetchColumn() == 0) {
                    $error_message = "Selected movie does not exist.";
                } else {
                    // Check if reviewer exists
                    $check_reviewer = $pdo->prepare("SELECT COUNT(*) FROM Reviewer WHERE rID = ?");
                    $check_reviewer->execute([$reviewer_id]);
                    if ($check_reviewer->fetchColumn() == 0) {
                        $error_message = "Selected reviewer does not exist.";
                    } else {
                        // Insert rating
                        $stmt = $pdo->prepare("INSERT INTO Rating (rID, mID, stars, ratingDate) VALUES (?, ?, ?, ?)");
                        $stmt->execute([$reviewer_id, $movie_id, $stars, $ratingDate]);
                        // Redirect to refresh the page and show updated data
                        header("Location: " . $_SERVER['PHP_SELF'] . "?success=rating_added");
                        exit;
                    }
                }
            } catch (PDOException $e) {
                $error_message = "Error adding rating: " . $e->getMessage();
            }
        }
    } else {
        $error_message = "Missing required fields for rating.";
    }
}

// Handle form submission for adding new movie
if (($_POST['action'] ?? '') === 'add_movie') {
    if (isset($_POST['movie_id'], $_POST['title'], $_POST['year'])) {
        $movie_id = (int)$_POST['movie_id'];
        $title = trim($_POST['title']);
        $year = (int)$_POST['year'];
        $director = !empty($_POST['director']) ? trim($_POST['director']) : null;
        
        // Validate inputs
        if (empty($title)) {
            $error_message = "Movie title cannot be empty.";
        } elseif ($year < 1888 || $year > 2030) {
            $error_message = "Year must be between 1888 and 2030.";
        } else {
            try {
                // Check if movie ID already exists
                $check_stmt = $pdo->prepare("SELECT COUNT(*) FROM Movie WHERE mID = ?");
                $check_stmt->execute([$movie_id]);
                if ($check_stmt->fetchColumn() > 0) {
                    $error_message = "Movie ID already exists. Please use a different ID.";
                } else {
                    $stmt = $pdo->prepare("INSERT INTO Movie (mID, title, year, director) VALUES (?, ?, ?, ?)");
                    $stmt->execute([$movie_id, $title, $year, $director]);
                    // Redirect to refresh the page and show updated data
                    header("Location: " . $_SERVER['PHP_SELF'] . "?success=movie_added");
                    exit;
                }
            } catch (PDOException $e) {
                $error_message = "Error adding movie: " . $e->getMessage();
            }
        }
    } else {
        $error_message = "Missing required fields for movie.";
    }
}

// Handle form submission for adding new reviewer
if (($_POST['action'] ?? '') === 'add_reviewer') {
    if (isset($_POST['reviewer_id'], $_POST['name'])) {
        $reviewer_id = (int)$_POST['reviewer_id'];
        $name = trim($_POST['name']);
        
        // Validate inputs
        if (empty($name)) {
            $error_message = "Reviewer name cannot be empty.";
        } else {
            try {
                // Check if reviewer ID already exists
                $check_stmt = $pdo->prepare("SELECT COUNT(*) FROM Reviewer WHERE rID = ?");
                $check_stmt->execute([$reviewer_id]);
                if ($check_stmt->fetchColumn() > 0) {
                    $error_message = "Reviewer ID already exists. Please use a different ID.";
                } else {
                    $stmt = $pdo->prepare("INSERT INTO Reviewer (rID, name) VALUES (?, ?)");
                    $stmt->execute([$reviewer_id, $name]);
                    // Redirect to refresh the page and show updated data
                    header("Location: " . $_SERVER['PHP_SELF'] . "?success=reviewer_added");
                    exit;
                }
            } catch (PDOException $e) {
                $error_message = "Error adding reviewer: " . $e->getMessage();
            }
        }
    } else {
        $error_message = "Missing required fields for reviewer.";
    }
}

// Pagination settings
$records_per_page = 10;
$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
$offset = ($page - 1) * $records_per_page;

// Get total number of ratings for pagination
$count_stmt = $pdo->query("SELECT COUNT(*) FROM Rating r 
                          JOIN Movie m ON r.mID = m.mID 
                          JOIN Reviewer rv ON r.rID = rv.rID");
$total_records = $count_stmt->fetchColumn();
$total_pages = ceil($total_records / $records_per_page);

// Fetch movie ratings with pagination
$stmt = $pdo->prepare("
    SELECT 
        m.title, 
        m.year, 
        m.director, 
        rv.name as reviewer_name, 
        r.stars, 
        r.ratingDate 
    FROM Rating r 
    JOIN Movie m ON r.mID = m.mID 
    JOIN Reviewer rv ON r.rID = rv.rID 
    ORDER BY r.ratingDate DESC, m.title ASC 
    LIMIT :limit OFFSET :offset
");
$stmt->bindValue(':limit', $records_per_page, PDO::PARAM_INT);
$stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
$stmt->execute();
$ratings = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Get movies and reviewers for dropdowns
$movies = $pdo->query("SELECT mID, title FROM Movie ORDER BY title")->fetchAll(PDO::FETCH_ASSOC);
$reviewers = $pdo->query("SELECT rID, name FROM Reviewer ORDER BY name")->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Movie Rating System</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1, h2 { color: #333; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; font-weight: bold; }
        tr:hover { background-color: #f5f5f5; }
        .form-section { background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .form-group { margin: 15px 0; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input, select, textarea { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        button { background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; margin: 5px; }
        button:hover { background: #0056b3; }
        .pagination { text-align: center; margin: 20px 0; }
        .pagination a, .pagination span { display: inline-block; padding: 8px 16px; margin: 0 2px; text-decoration: none; background: #f8f9fa; border: 1px solid #ddd; border-radius: 4px; }
        .pagination a:hover { background: #007bff; color: white; }
        .pagination .current { background: #007bff; color: white; }
        .message { padding: 10px; margin: 10px 0; border-radius: 4px; }
        .success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .tabs { margin: 20px 0; }
        .tab-button { background: #f8f9fa; border: 1px solid #ddd; padding: 10px 20px; cursor: pointer; margin-right: 5px; border-radius: 4px 4px 0 0; }
        .tab-button.active { background: #007bff; color: white; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
    </style>
    <script>
        function showTab(tabName) {
            // Hide all tab contents
            var contents = document.getElementsByClassName('tab-content');
            for (var i = 0; i < contents.length; i++) {
                contents[i].classList.remove('active');
            }
            
            // Remove active class from all buttons
            var buttons = document.getElementsByClassName('tab-button');
            for (var i = 0; i < buttons.length; i++) {
                buttons[i].classList.remove('active');
            }
            
            // Show selected tab and mark button as active
            document.getElementById(tabName).classList.add('active');
            event.target.classList.add('active');
        }
        
        // Generate suggested IDs
        function generateNextId(type) {
            // This is a simple client-side suggestion
            // Server-side validation will still check for duplicates
            var timestamp = new Date().getTime();
            var random = Math.floor(Math.random() * 1000);
            
            if (type === 'movie') {
                return 100 + (timestamp % 1000) + random % 100;
            } else if (type === 'reviewer') {
                return 200 + (timestamp % 1000) + random % 100;
            }
        }
        
        // Auto-suggest IDs when forms load
        window.onload = function() {
            var movieIdField = document.getElementById('movie_id_new');
            var reviewerIdField = document.getElementById('reviewer_id_new');
            
            if (movieIdField && !movieIdField.value) {
                movieIdField.placeholder = 'Suggested: ' + generateNextId('movie');
            }
            
            if (reviewerIdField && !reviewerIdField.value) {
                reviewerIdField.placeholder = 'Suggested: ' + generateNextId('reviewer');
            }
        }
    </script>
</head>
<body>
    <div class="container">
        <h1>🎬 Movie Rating System</h1>
        
        <?php 
        // Handle success messages from URL parameters
        if (isset($_GET['success'])) {
            switch ($_GET['success']) {
                case 'rating_added':
                    echo '<div class="message success">Rating added successfully!</div>';
                    break;
                case 'movie_added':
                    echo '<div class="message success">Movie added successfully!</div>';
                    break;
                case 'reviewer_added':
                    echo '<div class="message success">Reviewer added successfully!</div>';
                    break;
            }
        }
        
        if (isset($success_message)): ?>
            <div class="message success"><?php echo htmlspecialchars($success_message); ?></div>
        <?php endif; ?>
        
        <?php if (isset($error_message)): ?>
            <div class="message error"><?php echo htmlspecialchars($error_message); ?></div>
        <?php endif; ?>
        
        <h2>Movie Ratings</h2>
        <table>
            <thead>
                <tr>
                    <th>Movie Title</th>
                    <th>Year</th>
                    <th>Director</th>
                    <th>Reviewer</th>
                    <th>Rating</th>
                    <th>Date</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($ratings as $rating): ?>
                <tr>
                    <td><?php echo htmlspecialchars($rating['title']); ?></td>
                    <td><?php echo htmlspecialchars($rating['year']); ?></td>
                    <td><?php echo htmlspecialchars($rating['director'] ?: 'Unknown'); ?></td>
                    <td><?php echo htmlspecialchars($rating['reviewer_name']); ?></td>
                    <td><?php echo str_repeat('⭐', $rating['stars']); ?> (<?php echo $rating['stars']; ?>/5)</td>
                    <td><?php echo $rating['ratingDate'] ? htmlspecialchars($rating['ratingDate']) : 'No date'; ?></td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        
        <!-- Pagination -->
        <div class="pagination">
            <?php if ($page > 1): ?>
                <a href="?page=<?php echo $page - 1; ?>">« Previous</a>
            <?php endif; ?>
            
            <?php for ($i = 1; $i <= $total_pages; $i++): ?>
                <?php if ($i == $page): ?>
                    <span class="current"><?php echo $i; ?></span>
                <?php else: ?>
                    <a href="?page=<?php echo $i; ?>"><?php echo $i; ?></a>
                <?php endif; ?>
            <?php endfor; ?>
            
            <?php if ($page < $total_pages): ?>
                <a href="?page=<?php echo $page + 1; ?>">Next »</a>
            <?php endif; ?>
        </div>
        
        <p>Showing page <?php echo $page; ?> of <?php echo $total_pages; ?> (<?php echo $total_records; ?> total ratings)</p>
        
        <!-- Add Data Forms -->
        <h2>Add New Data</h2>
        <div class="tabs">
            <button class="tab-button active" onclick="showTab('add-rating')">Add Rating</button>
            <button class="tab-button" onclick="showTab('add-movie')">Add Movie</button>
            <button class="tab-button" onclick="showTab('add-reviewer')">Add Reviewer</button>
        </div>
        
        <!-- Add Rating Form -->
        <div id="add-rating" class="tab-content active">
            <div class="form-section">
                <h3>Add New Rating</h3>
                <form method="POST">
                    <input type="hidden" name="action" value="add_rating">
                    
                    <div class="form-group">
                        <label for="movie_id">Movie:</label>
                        <select name="movie_id" id="movie_id" required>
                            <option value="">Select a movie</option>
                            <?php foreach ($movies as $movie): ?>
                                <option value="<?php echo $movie['mID']; ?>">
                                    <?php echo htmlspecialchars($movie['title']); ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="form-group">
                        <label for="reviewer_id">Reviewer:</label>
                        <select name="reviewer_id" id="reviewer_id" required>
                            <option value="">Select a reviewer</option>
                            <?php foreach ($reviewers as $reviewer): ?>
                                <option value="<?php echo $reviewer['rID']; ?>">
                                    <?php echo htmlspecialchars($reviewer['name']); ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="form-group">
                        <label for="stars">Rating (1-5 stars):</label>
                        <select name="stars" id="stars" required>
                            <option value="">Select rating</option>
                            <option value="1">1 ⭐</option>
                            <option value="2">2 ⭐⭐</option>
                            <option value="3">3 ⭐⭐⭐</option>
                            <option value="4">4 ⭐⭐⭐⭐</option>
                            <option value="5">5 ⭐⭐⭐⭐⭐</option>
                        </select>
                    </div>
                    
                    <div class="form-group">
                        <label for="rating_date">Rating Date (optional):</label>
                        <input type="date" name="rating_date" id="rating_date">
                    </div>
                    
                    <button type="submit">Add Rating</button>
                </form>
            </div>
        </div>
        
        <!-- Add Movie Form -->
        <div id="add-movie" class="tab-content">
            <div class="form-section">
                <h3>Add New Movie</h3>
                <form method="POST">
                    <input type="hidden" name="action" value="add_movie">
                    
                    <div class="form-group">
                        <label for="movie_id_new">Movie ID:</label>
                        <input type="number" name="movie_id" id="movie_id_new" required min="1">
                    </div>
                    
                    <div class="form-group">
                        <label for="title">Movie Title:</label>
                        <input type="text" name="title" id="title" required maxlength="255">
                    </div>
                    
                    <div class="form-group">
                        <label for="year">Year:</label>
                        <input type="number" name="year" id="year" required min="1888" max="2030">
                    </div>
                    
                    <div class="form-group">
                        <label for="director">Director (optional):</label>
                        <input type="text" name="director" id="director" maxlength="255">
                    </div>
                    
                    <button type="submit">Add Movie</button>
                </form>
            </div>
        </div>
        
        <!-- Add Reviewer Form -->
        <div id="add-reviewer" class="tab-content">
            <div class="form-section">
                <h3>Add New Reviewer</h3>
                <form method="POST">
                    <input type="hidden" name="action" value="add_reviewer">
                    
                    <div class="form-group">
                        <label for="reviewer_id_new">Reviewer ID:</label>
                        <input type="number" name="reviewer_id" id="reviewer_id_new" required min="1">
                    </div>
                    
                    <div class="form-group">
                        <label for="name">Reviewer Name:</label>
                        <input type="text" name="name" id="name" required maxlength="255">
                    </div>
                    
                    <button type="submit">Add Reviewer</button>
                </form>
            </div>
        </div>
    </div>
</body>
</html>
