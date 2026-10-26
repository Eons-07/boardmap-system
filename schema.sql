-- BoardMap schema (structure only): database, schema, tables, keys, constraints.
-- Run seed.sql afterwards for sample data and demo queries.

-- ============================================
-- DATABASE & SCHEMA INITIALIZATION
-- ============================================
-- CREATE DATABASE boardmap_db; 

CREATE SCHEMA system_core;

-- ============================================
-- USERS TABLE
-- PURPOSE: Stores the accounts of students, administrators, and boarding-house owners.
-- PRIMARY KEY: user_id uniquely identifies every user.
-- ROLE: Determines whether the account belongs to a student, admin, or owner.
-- ============================================
CREATE TABLE system_core.users (
user_id SERIAL PRIMARY KEY,
full_name VARCHAR(150) NOT NULL,
email VARCHAR(150) UNIQUE NOT NULL,
password VARCHAR(255) NOT NULL,
contact_number VARCHAR(20),
role VARCHAR(30) NOT NULL DEFAULT 'student',
date_registered TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT users_role_check CHECK (role IN ('student', 'admin', 'owner'))
);

-- ============================================
-- BOARDING HOUSE OWNERS TABLE
-- PURPOSE: Stores information about people who own or manage boarding houses.
-- RELATIONSHIP: An owner may be connected to a user account through user_id.
-- ============================================
CREATE TABLE system_core.boarding_house_owners (
owner_id SERIAL PRIMARY KEY,
user_id INT UNIQUE,
name VARCHAR(150) NOT NULL,
email VARCHAR(150) UNIQUE NOT NULL,
contact_number VARCHAR(20),
address TEXT,
verification_status VARCHAR(30) DEFAULT 'pending',
CONSTRAINT owner_verification_check CHECK (
verification_status IN ('pending', 'verified', 'rejected')
),
CONSTRAINT fk_owner_user FOREIGN KEY (user_id) REFERENCES system_core.users(user_id) ON DELETE SET NULL
);

-- ============================================
-- LOCATIONS TABLE
-- PURPOSE: Stores standardized location information. Separated from boarding_houses
-- so location information can be reused and managed consistently.
-- LATITUDE & LONGITUDE: Used later for map-based features.
-- ============================================
CREATE TABLE system_core.locations (
location_id SERIAL PRIMARY KEY,
barangay_name VARCHAR(100) NOT NULL,
city VARCHAR(100) NOT NULL,
province VARCHAR(100),
latitude DECIMAL(10, 7),
longitude DECIMAL(10, 7)
);

-- ============================================
-- BOARDING HOUSES TABLE
-- PURPOSE: Central table of BoardMap storing main information about each boarding house.
-- RELATIONSHIPS:
-- owner_id -> identifies the boarding-house owner
-- location_id -> identifies the boarding-house location
-- ============================================
CREATE TABLE system_core.boarding_houses (
boarding_house_id SERIAL PRIMARY KEY,
owner_id INT NOT NULL,
location_id INT NOT NULL,
house_name VARCHAR(150) NOT NULL,
description TEXT,
capacity INT NOT NULL DEFAULT 0,
contact_number VARCHAR(20),
status VARCHAR(30) NOT NULL DEFAULT 'pending',
date_registered TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT boarding_house_capacity_check CHECK (capacity >= 0),
CONSTRAINT boarding_house_status_check CHECK (
status IN ('pending', 'approved', 'rejected', 'inactive')
),
CONSTRAINT fk_boarding_house_owner FOREIGN KEY (owner_id) REFERENCES system_core.boarding_house_owners(owner_id) ON DELETE CASCADE,
CONSTRAINT fk_boarding_house_location FOREIGN KEY (location_id) REFERENCES system_core.locations(location_id) ON DELETE RESTRICT
);

-- ============================================
-- AMENITIES TABLE
-- PURPOSE: Stores the master list of amenities available in boarding houses.
-- ============================================
CREATE TABLE system_core.amenities (
amenity_id SERIAL PRIMARY KEY,
amenity_name VARCHAR(100) UNIQUE NOT NULL,
description TEXT
);

-- ============================================
-- BOARDING HOUSE AMENITIES
-- PURPOSE: Connects boarding houses with amenities.
-- This is a JUNCTION TABLE creating a MANY-TO-MANY relationship.
-- ============================================
CREATE TABLE system_core.boarding_house_amenities (
boarding_house_id INT NOT NULL,
amenity_id INT NOT NULL,
PRIMARY KEY (boarding_house_id, amenity_id),
CONSTRAINT fk_bha_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE,
CONSTRAINT fk_bha_amenity FOREIGN KEY (amenity_id) REFERENCES system_core.amenities(amenity_id) ON DELETE CASCADE
);

-- ============================================
-- ROOMS TABLE
-- PURPOSE: Stores the different room types offered by each boarding house.
-- PRICE: Stores the price of a particular room type.
-- AVAILABLE_SLOTS: Shows how many spaces are currently available.
-- ============================================
CREATE TABLE system_core.rooms (
room_id SERIAL PRIMARY KEY,
boarding_house_id INT NOT NULL,
room_type VARCHAR(50) NOT NULL,
price DECIMAL(10, 2) NOT NULL,
capacity INT NOT NULL DEFAULT 1,
available_slots INT NOT NULL DEFAULT 0,
status VARCHAR(30) NOT NULL DEFAULT 'available',
CONSTRAINT room_price_check CHECK (price >= 0),
CONSTRAINT room_capacity_check CHECK (capacity > 0),
CONSTRAINT room_available_slots_check CHECK (
available_slots >= 0 AND available_slots <= capacity
),
CONSTRAINT room_status_check CHECK (
status IN ('available', 'full', 'inactive')
),
CONSTRAINT fk_room_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE
);

-- ============================================
-- BOARDING HOUSE IMAGES
-- PURPOSE: Stores image URLs and captions for boarding houses.
-- A boarding house can have multiple images.
-- ============================================
CREATE TABLE system_core.boarding_house_images (
image_id SERIAL PRIMARY KEY,
boarding_house_id INT NOT NULL,
image_url TEXT NOT NULL,
caption VARCHAR(255),
upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT fk_image_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE
);

-- ============================================
-- REVIEWS AND RATINGS
-- PURPOSE: Stores student reviews and ratings for boarding houses.
-- A user can review a boarding house.
-- A user cannot review the same boarding house more than once.
-- ============================================
CREATE TABLE system_core.reviews (
review_id SERIAL PRIMARY KEY,
user_id INT NOT NULL,
boarding_house_id INT NOT NULL,
rating INT NOT NULL,
comment TEXT,
review_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT review_rating_check CHECK (rating BETWEEN 1 AND 5),
CONSTRAINT fk_review_user FOREIGN KEY (user_id) REFERENCES system_core.users(user_id) ON DELETE CASCADE,
CONSTRAINT fk_review_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE,
CONSTRAINT unique_user_boarding_house_review UNIQUE (user_id, boarding_house_id)
);

-- ============================================
-- USER PREFERENCES
-- PURPOSE: Stores what a student is looking for.
-- These preferences can later be used by the recommendation system
-- to find suitable boarding houses.
-- ============================================
CREATE TABLE system_core.user_preferences (
preference_id SERIAL PRIMARY KEY,
user_id INT NOT NULL,
preferred_budget DECIMAL(10, 2),
preferred_location INT,
preferred_room_type VARCHAR(50),
distance_preference DECIMAL(10, 2),
date_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT preference_budget_check CHECK (
preferred_budget IS NULL OR preferred_budget >= 0
),
CONSTRAINT preference_distance_check CHECK (
distance_preference IS NULL OR distance_preference >= 0
),
CONSTRAINT fk_preference_user FOREIGN KEY (user_id) REFERENCES system_core.users(user_id) ON DELETE CASCADE,
CONSTRAINT fk_preference_location FOREIGN KEY (preferred_location) REFERENCES system_core.locations(location_id) ON DELETE SET NULL
);

-- ============================================
-- USER PREFERENCE AMENITIES
-- PURPOSE: Junction table linking a saved preference to the amenities the student wants.
-- It replaces the old text list so each amenity is one validated row.
-- ============================================
CREATE TABLE system_core.user_preference_amenities (
preference_id INT NOT NULL,
amenity_id INT NOT NULL,
PRIMARY KEY (preference_id, amenity_id),
CONSTRAINT fk_pref_amenity_preference FOREIGN KEY (preference_id) REFERENCES system_core.user_preferences(preference_id) ON DELETE CASCADE,
CONSTRAINT fk_pref_amenity_amenity FOREIGN KEY (amenity_id) REFERENCES system_core.amenities(amenity_id) ON DELETE CASCADE
);

-- ============================================
-- RECOMMENDATIONS
-- PURPOSE: Stores boarding houses recommended to a specific user.
-- RECOMMENDATION_SCORE: Represents the system-generated matching score.
-- ============================================
CREATE TABLE system_core.recommendations (
recommendation_id SERIAL PRIMARY KEY,
user_id INT NOT NULL,
boarding_house_id INT NOT NULL,
recommendation_score DECIMAL(5, 2),
recommendation_reason TEXT,
generated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT recommendation_score_check CHECK (
recommendation_score IS NULL OR recommendation_score BETWEEN 0 AND 100
),
CONSTRAINT fk_recommendation_user FOREIGN KEY (user_id) REFERENCES system_core.users(user_id) ON DELETE CASCADE,
CONSTRAINT fk_recommendation_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE
);

-- ============================================
-- MACHINE LEARNING PREDICTION RESULTS
-- PURPOSE: Stores results produced by the future machine-learning recommendation component.
-- MODEL_VERSION: Identifies which ML model generated the prediction.
-- ============================================
CREATE TABLE system_core.ml_prediction_results (
prediction_id SERIAL PRIMARY KEY,
user_id INT NOT NULL,
boarding_house_id INT NOT NULL,
predicted_suitability_score DECIMAL(5, 2),
model_version VARCHAR(50),
prediction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT prediction_score_check CHECK (
predicted_suitability_score IS NULL OR predicted_suitability_score BETWEEN 0 AND 100
),
CONSTRAINT fk_prediction_user FOREIGN KEY (user_id) REFERENCES system_core.users(user_id) ON DELETE CASCADE,
CONSTRAINT fk_prediction_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE
);

-- ============================================
-- FAVORITES
-- PURPOSE: Stores boarding houses saved/favorited by students.
-- UNIQUE: A user cannot favorite the same boarding house twice.
-- ============================================
CREATE TABLE system_core.favorites (
favorite_id SERIAL PRIMARY KEY,
user_id INT NOT NULL,
boarding_house_id INT NOT NULL,
date_added TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT fk_favorite_user FOREIGN KEY (user_id) REFERENCES system_core.users(user_id) ON DELETE CASCADE,
CONSTRAINT fk_favorite_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE,
CONSTRAINT unique_user_favorite UNIQUE (user_id, boarding_house_id)
);

-- ============================================
-- REPORTS
-- PURPOSE: Stores reports submitted by users about boarding houses.
-- EXAMPLES: Incorrect information, Incorrect price, Listing issues, Other concerns
-- ============================================
CREATE TABLE system_core.reports (
report_id SERIAL PRIMARY KEY,
user_id INT NOT NULL,
boarding_house_id INT NOT NULL,
report_type VARCHAR(100) NOT NULL,
description TEXT NOT NULL,
status VARCHAR(30) NOT NULL DEFAULT 'pending',
report_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
CONSTRAINT report_status_check CHECK (
status IN ('pending', 'reviewing', 'resolved', 'rejected')
),
CONSTRAINT fk_report_user FOREIGN KEY (user_id) REFERENCES system_core.users(user_id) ON DELETE CASCADE,
CONSTRAINT fk_report_boarding_house FOREIGN KEY (boarding_house_id) REFERENCES system_core.boarding_houses(boarding_house_id) ON DELETE CASCADE
);
