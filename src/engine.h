#pragma once

#include <iostream>
#include <chrono>
#include <thread>
#include <random>

#include <vk_types.h>
#include <vk_descriptors.h>
#include <vk_pipelines.h>
#include <vk_loader.h>

struct DeletionQueue {
	std::deque< std::function< void() > > deletors;

	// called when we add new Vulkan objects
	void push_function( std::function< void() >&& function ) {
		deletors.push_back( function );
	}

	// called during Cleanup()
	void flush() {
		// reverse iterate the deletion queue to execute all the functions
		for ( auto it = deletors.rbegin(); it != deletors.rend(); it++ ) {
			( *it )(); //call functors
		}
		deletors.clear();
	}
};

struct frameData_t {
	// frame sync primitives
	VkSemaphore swapchainSemaphore;
	VkFence renderFence;

	// command buffer + allocator
	VkCommandPool commandPool;
	VkCommandBuffer mainCommandBuffer;

	// handling frame-local resources
	DeletionQueue deletionQueue;

	// descriptor pool management
	DescriptorAllocatorGrowable frameDescriptors;
};

// common configuration across all shaders
struct GlobalData {
	glm::uvec2 presentBufferResolution;
	glm::uvec2 accumulatorResolution;
	glm::vec3 mouseLoc;

	int frameNumber{ 0 };
	int reset{ 1 };

	float brightnessScalar{ 1.0f };
	float resolutionScalar{ 1.0f };

	// for the view rays
	glm::vec3 viewBasisX{ 1.0f, 0.0f, 0.0f };
	glm::vec3 viewBasisY{ 0.0f, 1.0f, 0.0f };
	glm::vec3 viewBasisZ{ 0.0f, 0.0f, 1.0f };

	// for rotating the plane within the box
	glm::vec3 planeBasisX{ 1.0f, 0.0f, 0.0f };
	glm::vec3 planeBasisY{ 0.0f, 1.0f, 0.0f };
	glm::vec3 planeBasisZ{ 0.0f, 0.0f, 1.0f };

	// zooming in and out
	float zoomFactor{ 3.0f };

	int gridBaseDim = 128;
	int gridDivisions = 64;

	float angleScale = 1.0f;

	float panelMaskSize = 0.75f;

	int linearFilter = 0;
	int numRepeats = 1;

	// simulation parameters
	float timeStep = 1.2f;
	float density = 1.0f; // to determine intertia
	float evaporationRate = 0.001f;
	float depositionRate = 0.1f;
	float minVolume = 0.01f;
	float friction = 0.05f;

	int maxHeight = 0;
};

// smallest scope CPU->GPU passing of information
struct PushConstants {
	uint32_t wangSeed;
};

constexpr unsigned int FRAME_OVERLAP = 2;
constexpr bool useValidationLayers = true;

struct ComputeEffect {
	// pipeline is the thing we use to invoke this shader pass
	VkPipeline pipeline;

	// pipeline layout gives us what we need for sending push constants and buffer attachments
	VkPipelineLayout pipelineLayout;

	// this is the descriptor set layout for this particular compute effect (UBO + any SSBOs + any images/textures)
	VkDescriptorSetLayout descriptorSetLayout;
	VkDescriptorSet descriptorSet;

	// retained state for the push constants
	PushConstants pushConstants;

	// so we can have the main loop code local to the declaration
	std::function< void( VkCommandBuffer cmd ) > invoke;
};

inline uint32_t genWangSeed () {
	static thread_local std::mt19937 seedRNG( [] {
	// RNG ( mostly for generating GPU-side RNG seed)
		std::random_device rd;
		std::seed_seq seq{  rd(), rd(), rd(), rd(), rd(), rd(), rd(), rd() };
		return std::mt19937( seq );
	} () );

	// float x = std::uniform_real_distribution< float >( min, max )( seedRNG );
	return std::uniform_int_distribution< uint32_t >{}( seedRNG );
}

class PrometheusInstance {
public:

// data/storage resources
	AllocatedBuffer GlobalUBO;
	GlobalData globalData; // goes into the UBO

	// the output buffer resolution
	VkExtent2D ImageBufferResolution;

	// preparing output for the swapchain
	ComputeEffect BufferPresent;
	AllocatedImage Accumulator;

	// the buffer used to store the lenticular LUT
	VkExtent3D LenticularLUTResolution;
	AllocatedImage LenticularLUT;

	// resolving the lenticular LUT
	ComputeEffect LenticularResolve;

	// resolving the output image
	ComputeEffect OutputResolve;

	// holding the erosion sim state
	AllocatedImage Heightmap;
	ComputeEffect HeightmapErode;

	// engine triggers
	bool resizeRequest { false };
	bool isInitialized { false };
	bool stopRendering { false };
	int frameNumber { 0 };

	void initDefaultData ();
	// for buffer setup
	AllocatedBuffer createBuffer( size_t allocSize, VkBufferUsageFlags usage, VmaMemoryUsage memoryUsage );
	void destroyBuffer( const AllocatedBuffer& buffer );

	// basic Vulkan necessities, environmental handles
	VkInstance instance;						// Vulkan library handle
	VkDebugUtilsMessengerEXT debugMessenger;	// debug output messenger
	VkPhysicalDevice physicalDevice;			// GPU handle for the physical device in use
	VkDevice device;							// the abstract device that we interact with
	VkSurfaceKHR surface;						// the Vulkan window surface

	// an image to draw into and eventually pass to the swapchain
	AllocatedImage drawImage;
	AllocatedImage depthImage;
	VkExtent2D drawExtent;
	float renderScale = 1.0f;

	// some helper functions for allocating textures
	AllocatedImage createImage ( VkExtent3D size, VkFormat format, VkImageUsageFlags usage, bool mipmapped = false ); // storage image type
	AllocatedImage createImage ( void* data, VkExtent3D size, VkFormat format, VkImageUsageFlags usage, bool mipmapped = false ); // loaded from disk
	void updateImage( AllocatedImage& image, void* data, int bytesPerTexel );
	void screenshot(); // save the contents of the framebuffer
	void destroyImage ( const AllocatedImage& img );

	void SetDebugName( VkObjectType type, uint64_t handle, const char* name );

	// and some default textures
	AllocatedImage whiteImage;
	AllocatedImage blackImage;
	AllocatedImage greyImage;

	// and default sampler types
	VkSampler defaultSamplerLinear;
	VkSampler defaultSamplerNearest;

	// our frameData struct, which contains command pool/buffer + sync primitive handles
	frameData_t frameData[ FRAME_OVERLAP ];
	frameData_t& getCurrentFrame () { return frameData[ frameNumber % FRAME_OVERLAP ]; }

	VkFence immediateFence;
	VkCommandBuffer immediateCommandBuffer;
	VkCommandPool immediateCommandPool;
	void immediateSubmit( std::function< void( VkCommandBuffer cmd ) > && function );
	DescriptorAllocatorGrowable globalDescriptorAllocator;

	VkDescriptorSet drawImageDescriptors;
	VkDescriptorSetLayout drawImageDescriptorLayout;

	// the queue that we submit work to
	VkQueue graphicsQueue;
	uint32_t graphicsQueueFamilyIndex;

	// window size, swapchain size
	VkExtent2D windowExtent { 0,0 };
	VkExtent2D swapchainExtent;

	// swapchain handles
	VkSwapchainKHR swapchain;
	VkFormat swapchainImageFormat;
	std::vector< VkImage > swapchainImages;
	std::vector< VkImageView > swapchainImageViews;
	std::vector< VkSemaphore > swapchainPresentSemaphores;

	// handle for the AMD Vulkan Memory Allocator
	VmaAllocator allocator;

	// deletion queue automatically managing global resources
	DeletionQueue mainDeletionQueue;

	struct SDL_Window* window{ nullptr };
	static PrometheusInstance& Get ();

	void Init ();
	void Draw ();
	void MainLoop ();
	void ShutDown ();

private:
	// init helpers
	void initVulkan ();
	void initSwapchain ();
	void initCommandStructures ();
	void initSyncStructures ();
	void initDescriptors ();
	void initComputePasses ();
	void initImgui ();
	void initResources ();

	// main loop helpers
	void drawImgui ( VkCommandBuffer cmd, VkImageView targetImageView );

	// swapchain helpers
	void resizeSwapchain ();
	void createSwapchain ( uint32_t w, uint32_t h );
	void destroySwapchain ();
};