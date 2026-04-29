from google.cloud import vision

def test_image(image_path):
    client = vision.ImageAnnotatorClient()

    with open(image_path, "rb") as image_file:
        content = image_file.read()

    image = vision.Image(content=content)

    response = client.label_detection(image=image)
    labels = response.label_annotations

    print("Detected labels:")
    for label in labels[:5]:
        print(f"- {label.description} ({label.score:.2f})")


if __name__ == "__main__":
    test_image("chicken.jpg")